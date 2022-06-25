Code.require_file "../../../integration_test/support/types.exs", __DIR__

defmodule Ecto.Query.PlannerTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Query.Planner
  alias Ecto.Query.JoinExpr

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field :text, :string
      field :temp, :boolean, virtual: true
      field :posted, :naive_datetime
      field :uuid, :binary_id
      field :crazy_comment, :string

      belongs_to :post, Ecto.Query.PlannerTest.Post

      belongs_to :crazy_post, Ecto.Query.PlannerTest.Post,
        where: [title: "crazypost"]

      belongs_to :crazy_post_with_list, Ecto.Query.PlannerTest.Post,
        where: [title: {:in, ["crazypost1", "crazypost2"]}],
        foreign_key: :crazy_post_id,
        define_field: false

      has_many :post_comments, through: [:post, :comments]
      has_many :comment_posts, Ecto.Query.PlannerTest.CommentPost
    end
  end

  defmodule CommentPost do
    use Ecto.Schema

    schema "comment_posts" do
      belongs_to :comment, Comment
      belongs_to :post, Post
      belongs_to :special_comment, Comment, where: [text: nil]
      belongs_to :special_long_comment, Comment, where: [text: {:fragment, "LEN(?) > 100"}]

      field :deleted, :boolean
    end

    def inactive() do
      dynamic([row], row.deleted)
    end
  end

  defmodule Author do
    use Ecto.Schema

    embedded_schema do
      field :name, :string
    end
  end

  defmodule PostMeta do
    use Ecto.Schema

    embedded_schema do
      field :slug, :string
      embeds_one :author, Author
    end
  end

  defmodule Post do
    use Ecto.Schema

    @primary_key {:id, CustomPermalink, []}
    @schema_prefix "my_prefix"
    schema "posts" do
      field :title, :string, source: :post_title
      field :text, :string
      field :code, :binary
      field :posted, :naive_datetime
      field :visits, :integer
      field :links, {:array, CustomPermalink}
      field :prefs, {:map, :string}
      field :payload, :map, load_in_query: false
      field :status, Ecto.Enum, values: [:draft, :published, :deleted]

      embeds_one :meta, PostMeta
      embeds_many :metas, PostMeta

      has_many :comments, Ecto.Query.PlannerTest.Comment
      has_many :extra_comments, Ecto.Query.PlannerTest.Comment
      has_many :special_comments, Ecto.Query.PlannerTest.Comment, where: [text: {:not, nil}]
      many_to_many :crazy_comments, Comment, join_through: CommentPost, where: [text: "crazycomment"]
      many_to_many :crazy_comments_with_list, Comment, join_through: CommentPost, where: [text: {:in, ["crazycomment1", "crazycomment2"]}], join_where: [deleted: true]
      many_to_many :crazy_comments_without_schema, Comment, join_through: "comment_posts", join_where: [deleted: true]
    end
  end

  defp plan(query, operation \\ :all) do
    {query, params, key} = Planner.plan(query, operation, Ecto.TestAdapter)
    {cast_params, dump_params} = Enum.unzip(params)
    {query, cast_params, dump_params, key}
  end

  defp normalize(query, operation \\ :all) do
    normalize_with_params(query, operation) |> elem(0)
  end

  defp normalize_with_params(query, operation \\ :all) do
    {query, cast_params, dump_params, _key} = plan(query, operation)

    {query, select} =
      query
      |> Planner.ensure_select(operation == :all)
      |> Planner.normalize(operation, Ecto.TestAdapter, 0)

    {query, cast_params, dump_params, select}
  end

  defp select_fields(fields, ix) do
    for field <- fields do
      {{:., [], [{:&, [], [ix]}, field]}, [], []}
    end
  end

  test "plan: merges all parameters" do
    union = from p in Post, select: {p.title, ^"union"}
    subquery = from Comment, where: [text: ^"subquery"]

    query =
      from p in Post,
        select: {p.title, ^"select"},
        join: c in subquery(subquery),
        on: c.text == ^"join",
        left_join: d in assoc(p, :comments),
        union_all: ^union,
        windows: [foo: [partition_by: fragment("?", ^"windows")]],
        where: p.title == ^"where",
        group_by: p.title == ^"group_by",
        having: p.title == ^"having",
        order_by: [asc: fragment("?", ^"order_by")],
        limit: ^0,
        offset: ^1

    {_query, cast_params, dump_params, _key} = plan(query)
    assert cast_params ==
             ["select", "subquery", "join", "where", "group_by", "having", "windows"] ++
               ["union", "order_by", 0, 1]

    assert dump_params ==
             ["select", "subquery", "join", "where", "group_by", "having", "windows"] ++
               ["union", "order_by", 0, 1]
  end

  test "plan: checks from" do
    assert_raise Ecto.QueryError, ~r"query must have a from expression", fn ->
      plan(%Ecto.Query{})
    end
  end

  test "plan: casts values" do
    {_query, cast_params, dump_params, _key} = plan(Post |> where([p], p.id == ^"1"))
    assert cast_params == [1]
    assert dump_params == [1]

    exception = assert_raise Ecto.Query.CastError, fn ->
      plan(Post |> where([p], p.title == ^1))
    end

    assert Exception.message(exception) =~ "value `1` in `where` cannot be cast to type :string"
    assert Exception.message(exception) =~ "where: p0.title == ^1"
  end

  test "plan: Ecto.Query struct as right-side value of in operator" do
    query = from(Post)

    exception = assert_raise Ecto.QueryError, fn ->
      plan(Post |> where([p], p.id in ^query))
    end

    assert Exception.message(exception) =~ "an Ecto.Query struct is not supported as right-side value of `in` operator"
    assert Exception.message(exception) =~ "Did you mean to write `expr in subquery(query)` instead?"
  end

  test "plan: raises readable error on dynamic expressions/keyword lists" do
    dynamic = dynamic([p], p.id == ^"1")
    {_query, cast_params, dump_params, _key} = plan(Post |> where([p], ^dynamic))
    assert cast_params == [1]
    assert dump_params == [1]

    assert_raise Ecto.QueryError, ~r/dynamic expressions can only be interpolated/, fn ->
      plan(Post |> where([p], p.title == ^dynamic))
    end

    assert_raise Ecto.QueryError, ~r/keyword lists are only allowed/, fn ->
      plan(Post |> where([p], p.title == ^[foo: 1]))
    end
  end

  test "plan: casts and dumps custom types" do
    permalink = "1-hello-world"
    {_query, cast_params, dump_params, _key} = plan(Post |> where([p], p.id == ^permalink))
    assert cast_params == [1]
    assert dump_params == [1]
  end

  test "plan: casts and dumps binary ids" do
    uuid = "00010203-0405-4607-8809-0a0b0c0d0e0f"
    {_query, cast_params, dump_params, _key} = plan(Comment |> where([c], c.uuid == ^uuid))
    assert cast_params == ["00010203-0405-4607-8809-0a0b0c0d0e0f"]
    assert dump_params == [<<0, 1, 2, 3, 4, 5, 70, 7, 136, 9, 10, 11, 12, 13, 14, 15>>]

    assert_raise Ecto.Query.CastError,
                 ~r/`"00010203-0405-4607-8809"` cannot be dumped to type :binary_id/, fn ->
      uuid = "00010203-0405-4607-8809"
      plan(Comment |> where([c], c.uuid == ^uuid))
    end
  end

  test "plan: casts and dumps custom types in left side of in-expressions" do
    permalink = "1-hello-world"
    {_query, cast_params, dump_params, _key} = plan(Post |> where([p], ^permalink in p.links))
    assert cast_params == [1]
    assert dump_params == [1]

    message = ~r"value `\"1-hello-world\"` in `where` expected to be part of an array but matched type is :string"
    assert_raise Ecto.Query.CastError, message, fn ->
      plan(Post |> where([p], ^permalink in p.text))
    end
  end

  test "plan: casts and dumps custom types in right side of in-expressions" do
    datetime = ~N[2015-01-07 21:18:13.0]
    {_query, cast_params, dump_params, _key} = plan(Comment |> where([c], c.posted in ^[datetime]))
    assert cast_params == [~N[2015-01-07 21:18:13]]
    assert dump_params == [~N[2015-01-07 21:18:13]]

    permalink = "1-hello-world"
    {_query, cast_params, dump_params, _key} = plan(Post |> where([p], p.id in ^[permalink]))
    assert cast_params == [1]
    assert dump_params == [1]

    datetime = ~N[2015-01-07 21:18:13.0]
    {_query, cast_params, dump_params, _key} = plan(Comment |> where([c], c.posted in [^datetime]))
    assert cast_params == [~N[2015-01-07 21:18:13]]
    assert dump_params == [~N[2015-01-07 21:18:13]]

    permalink = "1-hello-world"
    {_query, cast_params, dump_params, _key} = plan(Post |> where([p], p.id in [^permalink]))
    assert cast_params == [1]
    assert dump_params == [1]

    {_query, cast_params, dump_params, _key} = plan(Post |> where([p], p.code in [^"abcd"]))
    assert cast_params == ["abcd"]
    assert dump_params == ["abcd"]

    {_query, cast_params, dump_params, _key} = plan(Post |> where([p], p.code in ^["abcd"]))
    assert cast_params == ["abcd"]
    assert dump_params == ["abcd"]
  end

  test "plan: casts values on update_all" do
    {_query, cast_params, dump_params, _key} = plan(Post |> update([p], set: [id: ^"1"]), :update_all)
    assert cast_params == [1]
    assert dump_params == [1]

    {_query, cast_params, dump_params, _key} = plan(Post |> update([p], set: [title: ^nil]), :update_all)
    assert cast_params == [nil]
    assert dump_params == [nil]

    {_query, cast_params, dump_params, _key} = plan(Post |> update([p], set: [title: nil]), :update_all)
    assert cast_params == []
    assert dump_params == []
  end

  test "plan: joins" do
    query = from(p in Post, join: c in "comments") |> plan |> elem(0)
    assert hd(query.joins).source == {"comments", nil}

    query = from(p in Post, join: c in Comment) |> plan |> elem(0)
    assert hd(query.joins).source == {"comments", Comment}

    query = from(p in Post, join: c in {"post_comments", Comment}) |> plan |> elem(0)
    assert hd(query.joins).source == {"post_comments", Comment}
  end

  test "plan: joins associations" do
    query = from(p in Post, join: assoc(p, :comments)) |> plan |> elem(0)
    assert %JoinExpr{on: on, source: source, assoc: nil, qual: :inner} = hd(query.joins)
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id()"

    query = from(p in Post, left_join: assoc(p, :comments)) |> plan |> elem(0)
    assert %JoinExpr{on: on, source: source, assoc: nil, qual: :left} = hd(query.joins)
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id()"

    query = from(p in Post, left_join: c in assoc(p, :comments), on: p.title == c.text) |> plan |> elem(0)
    assert %JoinExpr{on: on, source: source, assoc: nil, qual: :left} = hd(query.joins)
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id() and &0.title() == &1.text()"

    query = from(p in Post, left_join: c in assoc(p, :comments), on: p.meta["slug"] |> type(:string) == c.text) |> plan |> elem(0)
    assert %JoinExpr{on: on, source: source, assoc: nil, qual: :left} = hd(query.joins)
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id() and type(json_extract_path(&0.meta(), [\"slug\"]), :string) == &1.text()"

    query = from(p in Post, left_join: c in assoc(p, :comments), on: json_extract_path(p.meta, ["slug"]) |> type(:string) == c.text) |> plan |> elem(0)
    assert %JoinExpr{on: on, source: source, assoc: nil, qual: :left} = hd(query.joins)
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id() and type(json_extract_path(&0.meta(), [\"slug\"]), :string) == &1.text()"
  end

  test "plan: nested joins associations" do
    query = from(c in Comment, left_join: assoc(c, :post_comments)) |> plan |> elem(0)
    # The association query builder will optimize has_many through [:posts, :comments] by skipping :posts and joining
    # comments to comments on post_id
    assert {{"comments", _, _}, {"comments", _, _}} = query.sources
    assert [join1] = query.joins
    assert Enum.map(query.joins, & &1.ix) == [1]
    assert Macro.to_string(join1.on.expr) == "&0.post_id() == &1.post_id()"

    query = from(p in Comment, left_join: assoc(p, :post),
                               left_join: assoc(p, :post_comments)) |> plan |> elem(0)

    assert {{"comments", _, _}, {"posts", _, _}, {"comments", _, _}} = query.sources
    assert [join1, join2] = query.joins
    assert Enum.map(query.joins, & &1.ix) == [1, 2]
    assert Macro.to_string(join1.on.expr) == "&1.id() == &0.post_id()"
    assert Macro.to_string(join2.on.expr) == "&0.post_id() == &2.post_id()"

    query = from(p in Comment, left_join: assoc(p, :post_comments),
                               left_join: assoc(p, :post)) |> plan |> elem(0)
    assert {{"comments", _, _}, {"comments", _, _}, {"posts", _, _}} = query.sources
    assert [join1, join2] = query.joins
    assert Enum.map(query.joins, & &1.ix) == [1, 2]
    assert Macro.to_string(join1.on.expr) == "&0.post_id() == &1.post_id()"
    assert Macro.to_string(join2.on.expr) == "&2.id() == &0.post_id()"
  end

  test "plan: joins associations with custom queries" do
    query = from(p in Post, left_join: assoc(p, :special_comments)) |> plan |> elem(0)

    assert {{"posts", _, _}, {"comments", _, _}} = query.sources
    assert [join] = query.joins
    assert join.ix == 1
    assert Macro.to_string(join.on.expr) =~
             ~r"&1.post_id\(\) == &0.id\(\) and not[\s\(]is_nil\(&1.text\(\)\)\)?"
  end

  test "plan: nested joins associations with custom queries" do
    query = from(p in Post,
                   join: c1 in assoc(p, :special_comments),
                   join: p2 in assoc(c1, :post),
                   join: cp in assoc(c1, :comment_posts),
                   join: c2 in assoc(cp, :special_comment),
                   join: c3 in assoc(cp, :special_long_comment))
                   |> plan
                   |> elem(0)

    assert [join1, join2, join3, join4, join5] = query.joins
    assert {{"posts", _, _}, {"comments", _, _}, {"posts", _, _},
            {"comment_posts", _, _}, {"comments", _, _}, {"comments", _, _}} = query.sources

    assert Macro.to_string(join1.on.expr) =~
           ~r"&1.post_id\(\) == &0.id\(\) and not[\s\(]is_nil\(&1.text\(\)\)\)?"
    assert Macro.to_string(join2.on.expr) == "&2.id() == &1.post_id()"
    assert Macro.to_string(join3.on.expr) == "&3.comment_id() == &1.id()"
    assert Macro.to_string(join4.on.expr) == "&4.id() == &3.special_comment_id() and is_nil(&4.text())"
    assert Macro.to_string(join5.on.expr) ==
           "&5.id() == &3.special_long_comment_id() and fragment({:raw, \"LEN(\"}, {:expr, &5.text()}, {:raw, \") > 100\"})"
  end

  test "plan: raises on invalid binding index in join" do
    query =
      from(p in Post, as: :posts)
      |> join(:left, [{p, :foo}], assoc(p, :comments))

    assert_raise ArgumentError, ~r/invalid binding index/, fn ->
      plan(query)
    end
  end

  test "plan: cannot associate without schema" do
    query   = from(p in "posts", join: assoc(p, :comments))
    message = ~r"cannot perform association join on \"posts\" because it does not have a schema"

    assert_raise Ecto.QueryError, message, fn ->
      plan(query)
    end
  end

  test "plan: requires an association field" do
    query = from(p in Post, join: assoc(p, :title))

    assert_raise Ecto.QueryError, ~r"could not find association `title`", fn ->
      plan(query)
    end
  end

  test "plan: handles specific param type-casting" do
    value = NaiveDateTime.utc_now()
    {_, cast_params, dump_params, _} = from(p in Post, where: p.posted > datetime_add(^value, 1, "second")) |> plan()
    assert cast_params == [value]
    assert dump_params == [value]

    value = DateTime.utc_now()
    {_, cast_params, dump_params, _} = from(p in Post, where: p.posted > datetime_add(^value, 1, "second")) |> plan()
    assert cast_params == [value]
    assert dump_params == [value]

    value = ~N[2010-04-17 14:00:00]
    {_, cast_params, dump_params, _} =
      from(p in Post, where: p.posted > datetime_add(^"2010-04-17 14:00:00", 1, "second")) |> plan()
    assert cast_params == [value]
    assert dump_params == [value]
  end

  test "plan: generates a cache key" do
    {_query, _cast_params, _dump_params, key} = plan(from(Post, []))
    assert key == [:all, {:from, {"posts", Post, 69355382, "my_prefix"}, []}]

    query =
      from(
        p in Post,
        prefix: "hello",
        hints: ["hint"],
        select: 1,
        lock: "foo",
        where: is_nil(nil),
        or_where: is_nil(nil),
        join: c in Comment,
        hints: ["join hint"],
        prefix: "world",
        preload: :comments
      )

    {_query, _cast_params, _dump_params, key} = plan(%{query | prefix: "foo"})
    assert key == [:all,
                   {:lock, "foo"},
                   {:prefix, "foo"},
                   {:where, [{:and, {:is_nil, [], [nil]}}, {:or, {:is_nil, [], [nil]}}]},
                   {:join, [{:inner, {"comments", Comment, 38292156, "world"}, true, ["join hint"]}]},
                   {:from, {"posts", Post, 69355382, "hello"}, ["hint"]},
                   {:select, 1}]
  end

  test "plan: generates a cache key for in based on the adapter" do
    query = from(p in Post, where: p.id in ^[1, 2, 3])
    {_query, _params, key} = Planner.plan(query, :all, Ecto.TestAdapter)
    assert key == :nocache
  end

  test "plan: combination with uncacheable queries are uncacheable" do
    query1 =
      Post
      |> where([p], p.id in ^[1, 2, 3])
      |> select([p], p.id)

    query2 =
      Post
      |> where([p], p.id in [1, 2])
      |> select([p], p.id)
      |> distinct(true)

    {_, _, key} = query1 |> union_all(^query2) |> Planner.plan(:all, Ecto.TestAdapter)
    assert key == :nocache
  end

  test "plan: normalizes prefixes" do
    # No schema prefix in from
    {query, _, _, _} = from(Comment, select: 1) |> plan()
    assert query.sources == {{"comments", Comment, nil}}

    {query, _, _, _} = from(Comment, select: 1) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "global"}}

    {query, _, _, _} = from(Comment, prefix: "local", select: 1) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "local"}}

    # Schema prefix in from
    {query, _, _, _} = from(Post, select: 1) |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}}

    {query, _, _, _} = from(Post, select: 1) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}}

    {query, _, _, _} = from(Post, prefix: "local", select: 1) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"posts", Post, "local"}}

    # Schema prefix in join
    {query, _, _, _} = from(c in Comment, join: Post) |> plan()
    assert query.sources == {{"comments", Comment, nil}, {"posts", Post, "my_prefix"}}

    {query, _, _, _} = from(c in Comment, join: Post) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "global"}, {"posts", Post, "my_prefix"}}

    {query, _, _, _} = from(c in Comment, join: Post, prefix: "local") |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "global"}, {"posts", Post, "local"}}

    # Schema prefix in query join
    {query, _, _, _} = from(p in Post, join: ^from(c in Comment)) |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}, {"comments", Comment, nil}}

    {query, _, _, _} = from(p in Post, join: ^from(c in Comment)) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}, {"comments", Comment, "global"}}

    {query, _, _, _} = from(p in Post, join: ^from(c in Comment), prefix: "local") |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}, {"comments", Comment, "local"}}

    # No schema prefix in assoc join
    {query, _, _, _} = from(c in Comment, join: assoc(c, :comment_posts)) |> plan()
    assert query.sources == {{"comments", Comment, nil}, {"comment_posts", CommentPost, nil}}

    {query, _, _, _} = from(c in Comment, join: assoc(c, :comment_posts)) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "global"}, {"comment_posts", CommentPost, "global"}}

    {query, _, _, _} = from(c in Comment, join: assoc(c, :comment_posts), prefix: "local") |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "global"}, {"comment_posts", CommentPost, "local"}}

    # Schema prefix in assoc join
    {query, _, _, _} = from(c in Comment, join: assoc(c, :post)) |> plan()
    assert query.sources == {{"comments", Comment, nil}, {"posts", Post, "my_prefix"}}

    {query, _, _, _} = from(c in Comment, join: assoc(c, :post)) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "global"}, {"posts", Post, "my_prefix"}}

    {query, _, _, _} = from(c in Comment, join: assoc(c, :post), prefix: "local") |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "global"}, {"posts", Post, "local"}}

    # Schema prefix for assoc many-to-many joins
    {query, _, _, _} = from(c in Post, join: assoc(c, :crazy_comments)) |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}, {"comments", Comment, nil}, {"comment_posts", CommentPost, nil}}

    {query, _, _, _} = from(c in Post, join: assoc(c, :crazy_comments)) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}, {"comments", Comment, "global"}, {"comment_posts", CommentPost, "global"}}

    {query, _, _, _} = from(c in Post, join: assoc(c, :crazy_comments), prefix: "local") |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}, {"comments", Comment, "local"}, {"comment_posts", CommentPost, "local"}}

    # Schema prefix for assoc many-to-many joins (when join_through is a table name)
    {query, _, _, _} = from(c in Post, join: assoc(c, :crazy_comments_without_schema)) |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}, {"comments", Comment, nil}, {"comment_posts", nil, nil}}

    {query, _, _, _} = from(c in Post, join: assoc(c, :crazy_comments_without_schema)) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}, {"comments", Comment, "global"}, {"comment_posts", nil, "global"}}

    {query, _, _, _} = from(c in Post, join: assoc(c, :crazy_comments_without_schema), prefix: "local") |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}, {"comments", Comment, "local"}, {"comment_posts", nil, "local"}}

    # Schema prefix for assoc has through
    {query, _, _, _} = from(c in Comment, join: assoc(c, :post_comments)) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "global"}, {"comments", Comment, "global"}}

    {query, _, _, _} = from(c in Comment, join: assoc(c, :post_comments), prefix: "local") |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "global"}, {"comments", Comment, "local"}}
  end

  test "plan: combination queries" do
    {%{combinations: [{_, query}]}, _, _, cache} = from(c in Comment, union: ^from(c in Comment)) |> plan()
    assert query.sources == {{"comments", Comment, nil}}
    assert %Ecto.Query.SelectExpr{expr: {:&, [], [0]}} = query.select
    assert [:all, {:union, _}, _] = cache

    {%{combinations: [{_, query}]}, _, _, cache} = from(c in Comment, union: ^from(c in Comment, where: c in ^[1, 2, 3])) |> plan()
    assert query.sources == {{"comments", Comment, nil}}
    assert %Ecto.Query.SelectExpr{expr: {:&, [], [0]}} = query.select
    assert :nocache = cache
  end

  test "plan: normalizes prefixes for combinations" do
    # No schema prefix in from
    assert {%{combinations: [{_, union_query}]} = query, _, _, _} = from(Comment,  union: ^from(Comment)) |> plan()
    assert query.sources == {{"comments", Comment, nil}}
    assert union_query.sources == {{"comments", Comment, nil}}

    assert {%{combinations: [{_, union_query}]} = query, _, _, _} = from(Comment, union: ^from(Comment)) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "global"}}
    assert union_query.sources == {{"comments", Comment, "global"}}

    assert {%{combinations: [{_, union_query}]} = query, _, _, _} = from(Comment, prefix: "local", union: ^from(Comment)) |> plan()
    assert query.sources == {{"comments", Comment, "local"}}
    assert union_query.sources == {{"comments", Comment, nil}}

    assert {%{combinations: [{_, union_query}]} = query, _, _, _} = from(Comment, prefix: "local", union: ^from(Comment)) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "local"}}
    assert union_query.sources == {{"comments", Comment, "global"}}

    assert {%{combinations: [{_, union_query}]} = query, _, _, _} = from(Comment, prefix: "local", union: ^(from(Comment) |> Map.put(:prefix, "union"))) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"comments", Comment, "local"}}
    assert union_query.sources == {{"comments", Comment, "union"}}

    # With schema prefix
    assert {%{combinations: [{_, union_query}]} = query, _, _, _} = from(Post, union: ^from(p in Post)) |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}}
    assert union_query.sources == {{"posts", Post, "my_prefix"}}

    assert {%{combinations: [{_, union_query}]} = query, _, _, _} = from(Post, union: ^from(Post)) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"posts", Post, "my_prefix"}}
    assert union_query.sources == {{"posts", Post, "my_prefix"}}

    assert {%{combinations: [{_, union_query}]} = query, _, _, _} = from(Post, prefix: "local", union: ^from(Post)) |> plan()
    assert query.sources == {{"posts", Post, "local"}}
    assert union_query.sources == {{"posts", Post, "my_prefix"}}

    assert {%{combinations: [{_, union_query}]} = query, _, _, _} = from(Post, prefix: "local", union: ^from(Post)) |> Map.put(:prefix, "global") |> plan()
    assert query.sources == {{"posts", Post, "local"}}
    assert union_query.sources == {{"posts", Post, "my_prefix"}}

    # Deep-nested unions
    assert {%{combinations: [{_, upper_level_union_query}]} = query, _, _, _} = from(Comment, union: ^from(Comment, union: ^from(Comment))) |> plan()
    assert %{combinations: [{_, deeper_level_union_query}]} = upper_level_union_query
    assert query.sources == {{"comments", Comment, nil}}
    assert upper_level_union_query.sources == {{"comments", Comment, nil}}
    assert deeper_level_union_query.sources == {{"comments", Comment, nil}}

    assert {%{combinations: [{_, upper_level_union_query}]} = query, _, _, _} = from(Comment, union: ^from(Comment, union: ^from(Comment))) |> Map.put(:prefix, "global") |> plan()
    assert %{combinations: [{_, deeper_level_union_query}]} = upper_level_union_query
    assert query.sources == {{"comments", Comment, "global"}}
    assert upper_level_union_query.sources == {{"comments", Comment, "global"}}
    assert deeper_level_union_query.sources == {{"comments", Comment, "global"}}

    assert {%{combinations: [{_, upper_level_union_query}]} = query, _, _, _} = from(Comment, prefix: "local", union: ^from(Comment, union: ^from(Comment))) |> plan()
    assert %{combinations: [{_, deeper_level_union_query}]} = upper_level_union_query
    assert query.sources == {{"comments", Comment, "local"}}
    assert upper_level_union_query.sources == {{"comments", Comment, nil}}
    assert deeper_level_union_query.sources == {{"comments", Comment, nil}}

    assert {%{combinations: [{_, upper_level_union_query}]} = query, _, _, _} = from(Comment, prefix: "local", union: ^from(Comment, union: ^from(Comment))) |> Map.put(:prefix, "global") |> plan()
    assert %{combinations: [{_, deeper_level_union_query}]} = upper_level_union_query
    assert query.sources == {{"comments", Comment, "local"}}
    assert upper_level_union_query.sources == {{"comments", Comment, "global"}}
    assert deeper_level_union_query.sources == {{"comments", Comment, "global"}}
  end

  describe "plan: CTEs" do
    test "with uncacheable queries are uncacheable" do
      {_, _, _, cache} =
        Comment
        |> with_cte("cte", as: ^from(c in Comment, where: c.id in ^[1, 2, 3]))
        |> plan()

      assert cache == :nocache
    end

    test "on all" do
      {%{with_ctes: with_expr}, _, _, cache} =
        Comment
        |> with_cte("cte", as: ^put_query_prefix(Comment, "another"))
        |> plan()
      %{queries: [{"cte", query}]} = with_expr
      assert query.sources == {{"comments", Comment, "another"}}
      assert %Ecto.Query.SelectExpr{expr: {:&, [], [0]}} = query.select
      assert [
        :all,
        {:from, {"comments", Comment, _, nil}, []},
        {:non_recursive_cte, "cte",
         [:all, {:prefix, "another"}, {:from, {"comments", Comment, _, nil}, []}, {:select, {:&, _, [0]}}]}
      ] = cache

      {%{with_ctes: with_expr}, _, _, cache} =
        Comment
        |> with_cte("cte", as: ^(from(c in Comment, where: c in ^[1, 2, 3])))
        |> plan()
      %{queries: [{"cte", query}]} = with_expr
      assert query.sources == {{"comments", Comment, nil}}
      assert %Ecto.Query.SelectExpr{expr: {:&, [], [0]}} = query.select
      assert :nocache = cache

      {%{with_ctes: with_expr}, _, _, cache} =
        Comment
        |> recursive_ctes(true)
        |> with_cte("cte", as: fragment("SELECT * FROM comments WHERE id = ?", ^123))
        |> plan()
      %{queries: [{"cte", query_expr}]} = with_expr
      expr = {:fragment, [], [raw: "SELECT * FROM comments WHERE id = ", expr: {:^, [], [0]}, raw: ""]}
      assert expr == query_expr.expr
      assert [:all, {:from, {"comments", Comment, _, nil}, []}, {:recursive_cte, "cte", ^expr}] = cache
    end

    test "on update_all" do
      recent_comments =
        from(c in Comment,
          order_by: [desc: c.posted],
          limit: ^500,
          select: [:id]
        )
        |> put_query_prefix("another")

      {%{with_ctes: with_expr}, [500, "text"], [500, "text"], cache} =
        Comment
        |> with_cte("recent_comments", as: ^recent_comments)
        |> join(:inner, [c], r in "recent_comments", on: c.id == r.id)
        |> update(set: [text: ^"text"])
        |> select([c, r], c)
        |> plan(:update_all)

      %{queries: [{"recent_comments", cte}]} = with_expr
      assert {{"comments", Comment, "another"}} = cte.sources
      assert %{expr: {:^, [], [0]}, params: [{500, :integer}]} = cte.limit

      assert [:update_all, _, _, _, _, {:non_recursive_cte, "recent_comments", cte_cache}] = cache
      assert [
               :all,
               {:prefix, "another"},
               {:take, %{0 => {:any, [:id]}}},
               {:limit, {:^, [], [0]}},
               {:order_by, [[desc: _]]},
               {:from, {"comments", Comment, _, nil}, []},
               {:select, {:&, [], [0]}}
             ] = cte_cache
    end

    test "on delete_all" do
      recent_comments =
        from(c in Comment,
          order_by: [desc: c.posted],
          limit: ^500,
          select: [:id]
        )
        |> put_query_prefix("another")

      {%{with_ctes: with_expr}, [500, "text"], [500, "text"], cache} =
        Comment
        |> with_cte("recent_comments", as: ^recent_comments)
        |> join(:inner, [c], r in "recent_comments", on: c.id == r.id and c.text == ^"text")
        |> select([c, r], c)
        |> plan(:delete_all)

      %{queries: [{"recent_comments", cte}]} = with_expr
      assert {{"comments", Comment, "another"}} = cte.sources
      assert %{expr: {:^, [], [0]}, params: [{500, :integer}]} = cte.limit

      assert [:delete_all, _, _, _, {:non_recursive_cte, "recent_comments", cte_cache}] = cache
      assert [
               :all,
               {:prefix, "another"},
               {:take, %{0 => {:any, [:id]}}},
               {:limit, {:^, [], [0]}},
               {:order_by, [[desc: _]]},
               {:from, {"comments", Comment, _, nil}, []},
               {:select, {:&, [], [0]}}
             ] = cte_cache
    end

    test "prefixes" do
      {%{with_ctes: with_expr} = query, _, _, _} = Comment |> with_cte("cte", as: ^from(c in Comment)) |> plan()
      %{queries: [{"cte", cte_query}]} = with_expr
      assert query.sources == {{"comments", Comment, nil}}
      assert cte_query.sources == {{"comments", Comment, nil}}

      {%{with_ctes: with_expr} = query, _, _, _} = Comment |> with_cte("cte", as: ^from(c in Comment)) |> Map.put(:prefix, "global") |> plan()
      %{queries: [{"cte", cte_query}]} = with_expr
      assert query.sources == {{"comments", Comment, "global"}}
      assert cte_query.sources == {{"comments", Comment, "global"}}

      {%{with_ctes: with_expr} = query, _, _, _} = Comment |> with_cte("cte", as: ^(from(c in Comment) |> Map.put(:prefix, "cte"))) |> Map.put(:prefix, "global") |> plan()
      %{queries: [{"cte", cte_query}]} = with_expr
      assert query.sources == {{"comments", Comment, "global"}}
      assert cte_query.sources == {{"comments", Comment, "cte"}}
    end
  end

  test "normalize: validates literal types" do
    assert_raise Ecto.QueryError, fn ->
      Comment |> where([c], c.text == 123) |> normalize()
    end

    assert_raise Ecto.QueryError, fn ->
      Comment |> where([c], c.text == '123') |> normalize()
    end
  end

  test "normalize: casts atom values" do
    {_query, cast_params, dump_params, _key} = normalize_with_params(Post |> where([p], p.status == :draft))
    assert cast_params == []
    assert dump_params == []

    {_query, cast_params, dump_params, _key} = normalize_with_params(Post |> where([p], p.status == ^:published))
    assert cast_params == [:published]
    assert dump_params == ["published"]

    assert_raise Ecto.QueryError, ~r/value `:atoms_are_not_strings` cannot be dumped to type :string/, fn ->
      normalize(Post |> where([p], p.title == :atoms_are_not_strings))
    end

    assert_raise Ecto.QueryError, ~r/value `:unknown_status` cannot be dumped to type \{:parameterized, Ecto.Enum/, fn ->
      normalize(Post |> where([p], p.status == :unknown_status))
    end

    assert_raise Ecto.Query.CastError, ~r/value `:pinned` in `where` cannot be cast to type {:parameterized, Ecto.Enum/, fn ->
      normalize(Post |> where([p], p.status == ^:pinned))
    end
  end

  test "normalize: tagged types" do
    {query, cast_params, dump_params, _select} = from(Post, []) |> select([p], type(^"1", :integer))
                                              |> normalize_with_params()
    assert query.select.expr ==
           %Ecto.Query.Tagged{type: :integer, value: {:^, [], [0]}, tag: :integer}
    assert cast_params == [1]
    assert dump_params == [1]


    {query, cast_params, dump_params, _select} = from(Post, []) |> select([p], type(^"1", ^:integer))
                                              |> normalize_with_params()
    assert query.select.expr ==
           %Ecto.Query.Tagged{type: :integer, value: {:^, [], [0]}, tag: :integer}
    assert cast_params == [1]
    assert dump_params == [1]

    {query, cast_params, dump_params, _select} = from(Post, []) |> select([p], type(^"1", CustomPermalink))
                                              |> normalize_with_params()
    assert query.select.expr ==
           %Ecto.Query.Tagged{type: :id, value: {:^, [], [0]}, tag: CustomPermalink}
    assert cast_params == [1]
    assert dump_params == [1]

    {query, cast_params, dump_params, _select} = from(Post, []) |> select([p], type(^"1", p.visits))
                                              |> normalize_with_params()
    assert query.select.expr ==
           %Ecto.Query.Tagged{type: :integer, value: {:^, [], [0]}, tag: :integer}
    assert cast_params == [1]
    assert dump_params == [1]

    expected_tagged_query =
      %Ecto.Query.Tagged{
        tag: :binary,
        type: :binary,
        value:
          {:json_extract_path, [], [{{:., [], [{:&, [], [0]}, :meta]}, [], []}, ["slug"]]}
      }

    {query, cast_params, dump_params, _select} = from(Post, []) |> select([p], type(p.meta["slug"], :binary))
                                              |> normalize_with_params()
    assert query.select.expr == expected_tagged_query
    assert cast_params == []
    assert dump_params == []

    {query, cast_params, dump_params, _select} = from(Post, []) |> select([p], type(json_extract_path(p.meta, ["slug"]), :binary))
                                              |> normalize_with_params()
    assert query.select.expr == expected_tagged_query
    assert cast_params == []
    assert dump_params == []

    assert_raise Ecto.Query.CastError, ~r/value `"1"` in `select` cannot be cast to type Ecto.UUID/, fn ->
      from(Post, []) |> select([p], type(^"1", Ecto.UUID)) |> normalize
    end
  end

  test "normalize: select types" do
    param_type = Ecto.ParameterizedType.init(Ecto.Enum, values: [:foo, :bar])
    _ = from(p in "posts", select: type(fragment("cost"), :decimal)) |> normalize()
    _ = from(p in "posts", select: type(fragment("cost"), ^:decimal)) |> normalize()
    _ = from(p in "posts", select: type(fragment("cost"), ^param_type)) |> normalize()

    frag = ["$eq": 42]
    _ = from(p in "posts", select: type(fragment(^frag), :decimal)) |> normalize()
    _ = from(p in "posts", select: type(fragment(^frag), ^:decimal)) |> normalize()
    _ = from(p in "posts", select: type(fragment(^frag), ^param_type)) |> normalize()
  end

  test "normalize: late bindings with as" do
    query = from(Post, as: :posts, where: as(:posts).code == ^123) |> normalize()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.code() == ^0"

    assert_raise Ecto.QueryError, ~r/could not find named binding `as\(:posts\)`/, fn ->
      from(Post, where: as(:posts).code == ^123) |> normalize()
    end
  end

  test "normalize: late dynamic bindings with as" do
    as = :posts

    query = from(Post, as: :posts, where: as(^as).code == ^123) |> normalize()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.code() == ^0"

    query = from(Post, as: :posts, where: field(as(^as), :code) == ^123) |> normalize()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.code() == ^0"

    assert_raise Ecto.QueryError, ~r/could not find named binding `as\(:posts\)`/, fn ->
      from(Post, where: as(^as).code == ^123) |> normalize()
    end
  end

  test "normalize: creating dynamic bindings with as" do
    as = {:posts}

    query = from(Post, as: ^as, where: as(^as).code == ^123) |> normalize()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.code() == ^0"

    query = from(Post, as: ^as, where: field(as(^as), :code) == ^123) |> normalize()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.code() == ^0"

    assert_raise Ecto.QueryError, ~r/could not find named binding `as\(\{:posts\}\)`/, fn ->
      from(Post, where: as(^as).code == ^123) |> normalize()
    end

    query = from(Post, as: ^as, where: as(^as).code == ^123) |> normalize()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.code() == ^0"
  end

  test "normalize: late parent bindings with as" do
    child = from(c in Comment, where: parent_as(:posts).posted == c.posted)
    query = from(Post, as: :posts, join: c in subquery(child)) |> normalize()
    assert Macro.to_string(hd(hd(query.joins).source.query.wheres).expr) == "parent_as(:posts).posted() == &0.posted()"

    child = from(c in Comment, select: %{map: parent_as(:posts).posted})
    query = from(Post, as: :posts, join: c in subquery(child)) |> normalize()
    assert Macro.to_string(hd(query.joins).source.query.select.expr) == "%{map: parent_as(:posts).posted()}"

    assert_raise Ecto.SubQueryError, ~r/the parent_as in a subquery select used as a join can only access the `from` binding in query/, fn ->
      child = from(c in Comment, select: %{map: parent_as(:itself).posted})
      from(Post, as: :posts, join: c in subquery(child), as: :itself) |> normalize()
    end

    assert_raise Ecto.SubQueryError, ~r/could not find named binding `parent_as\(:posts\)`/, fn ->
      from(Post, join: c in subquery(child)) |> normalize()
    end

    assert_raise Ecto.QueryError, ~r/could not find named binding `parent_as\(:posts\)`/, fn ->
      from(Post, where: parent_as(:posts).code == ^123) |> normalize()
    end
  end

  test "normalize: late dynamic parent bindings with as" do
    as = :posts

    child = from(c in Comment, where: parent_as(^as).posted == c.posted)
    query = from(Post, as: :posts, join: c in subquery(child)) |> normalize()
    assert Macro.to_string(hd(hd(query.joins).source.query.wheres).expr) == "parent_as(:posts).posted() == &0.posted()"

    child = from(c in Comment, select: %{map: field(parent_as(^as), :posted)})
    query = from(Post, as: :posts, join: c in subquery(child)) |> normalize()
    assert Macro.to_string(hd(query.joins).source.query.select.expr) == "%{map: parent_as(:posts).posted()}"
  end

  test "normalize: nested parent_as" do
    child3 = from(c in Comment, where: parent_as(:posts).deleted == false, select: c.id)
    child2 = from(c in Comment, where: c.id in subquery(child3), select: c.id)
    child = from(c in Comment, where: parent_as(:posts).posted == c.posted and c.id in subquery(child2))

    query = from(Post, as: :posts, join: c in subquery(child)) |> normalize()
    assert Macro.to_string(hd(hd(query.joins).source.query.wheres).expr) =~ "parent_as(:posts).posted() == &0.posted()"
    assert Macro.to_string(hd(hd(query.joins).source.query.wheres).expr) =~ "in %Ecto.SubQuery{"
  end

  test "normalize: nested dynamic parent_as" do
    as = :posts
    child3 = from(c in Comment, where: parent_as(^as).deleted == false, select: c.id)
    child2 = from(c in Comment, where: c.id in subquery(child3), select: c.id)
    child = from(c in Comment, where: field(parent_as(^as), :posted) == c.posted and c.id in subquery(child2))

    query = from(Post, as: :posts, join: c in subquery(child)) |> normalize()
    assert Macro.to_string(hd(hd(query.joins).source.query.wheres).expr) =~ "parent_as(:posts).posted() == &0.posted()"
    assert Macro.to_string(hd(hd(query.joins).source.query.wheres).expr) =~ "in %Ecto.SubQuery{"
  end

  test "normalize: assoc join with wheres that have regular filters" do
    # Mixing both has_many and many_to_many
    {_query, cast_params, dump_params, _select} =
      from(post in Post,
        join: comment in assoc(post, :crazy_comments),
        join: post in assoc(comment, :crazy_post)) |> normalize_with_params()

    assert cast_params == ["crazycomment", "crazypost"]
    assert dump_params == ["crazycomment", "crazypost"]
  end

  test "normalize: has_many assoc join with wheres" do
    {query, cast_params, dump_params, _select} =
      from(comment in Comment, join: post in assoc(comment, :crazy_post_with_list)) |> normalize_with_params()

    assert inspect(query) =~ "join: p1 in Ecto.Query.PlannerTest.Post, on: p1.id == c0.crazy_post_id and p1.post_title in ^..."
    assert cast_params == ["crazypost1", "crazypost2"]
    assert dump_params == ["crazypost1", "crazypost2"]

    {query, cast_params, dump_params, _} =
      Ecto.assoc(%Comment{crazy_post_id: 1}, :crazy_post_with_list)
      |> normalize_with_params()

    assert inspect(query) =~ "where: p0.id == ^... and p0.post_title in ^..."
    assert cast_params == [1, "crazypost1", "crazypost2"]
    assert dump_params == [1, "crazypost1", "crazypost2"]
  end

  test "normalize: many_to_many assoc join with schema and wheres" do
    {query, cast_params, dump_params, _select} =
      from(post in Post, join: comment in assoc(post, :crazy_comments_with_list)) |> normalize_with_params()

    assert inspect(query) =~ "join: c1 in Ecto.Query.PlannerTest.Comment, on: c2.comment_id == c1.id and c1.text in ^... and c2.deleted == ^..."
    assert cast_params == ["crazycomment1", "crazycomment2", true]
    assert dump_params == ["crazycomment1", "crazycomment2", true]

    {query, cast_params, dump_params, _} =
      Ecto.assoc(%Post{id: 1}, :crazy_comments_with_list)
      |> normalize_with_params()

    assert inspect(query) =~ "join: c1 in Ecto.Query.PlannerTest.CommentPost, on: c0.id == c1.comment_id and c1.deleted == ^..."
    assert inspect(query) =~ "where: c1.post_id in ^... and c0.text in ^..."
    assert cast_params ==  [true, 1, "crazycomment1", "crazycomment2"]
    assert dump_params ==  [true, 1, "crazycomment1", "crazycomment2"]
  end

  test "normalize: many_to_many assoc join without schema and wheres" do
    {query, cast_params, dump_params, _select} =
      from(post in Post, join: comment in assoc(post, :crazy_comments_without_schema)) |> normalize_with_params()

    assert inspect(query) =~ "join: c1 in Ecto.Query.PlannerTest.Comment, on: c2.comment_id == c1.id and c2.deleted == ^..."
    assert cast_params == [true]
    assert dump_params == [true]

    {query, cast_params, dump_params, _} =
      Ecto.assoc(%Post{id: 1}, :crazy_comments_without_schema)
      |> normalize_with_params()

    assert inspect(query) =~ "join: c1 in \"comment_posts\", on: c0.id == c1.comment_id and c1.deleted == ^..."
    assert inspect(query) =~ "where: c1.post_id in ^..."
    assert cast_params ==  [true, 1]
    assert dump_params ==  [true, 1]
  end

  test "normalize: dumps in query expressions" do
    assert_raise Ecto.QueryError, ~r"cannot be dumped", fn ->
      normalize(from p in Post, where: p.posted == "2014-04-17 00:00:00")
    end
  end

  test "normalize: validate fields" do
    message = ~r"field `unknown` in `select` does not exist in schema Ecto.Query.PlannerTest.Comment"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(Comment, []) |> select([c], c.unknown)
      normalize(query)
    end

    exception = assert_raise Ecto.QueryError, fn ->
      query = from(Comment, []) |> select([c], c.postd)
      normalize(query)
    end

    assert exception.message =~ "field `postd` in `select` does not exist in schema"
    assert exception.message =~ "Did you mean one of:"
    assert exception.message =~ "* `posted`"
    assert exception.message =~ "* `post_id`"

    message = ~r"field `temp` in `select` is a virtual field in schema Ecto.Query.PlannerTest.Comment"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(Comment, []) |> select([c], c.temp)
      normalize(query)
    end

    message =
      ~r"field `crazy_post_with_list` in `select` is an association in schema Ecto.Query.PlannerTest.Comment. Did you mean to use `crazy_post_id`"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(Comment, []) |> select([c], c.crazy_post_with_list)
      normalize(query)
    end
  end

  test "normalize: allow virtual fields in type/2" do
    query = from(Comment, []) |> select([c], type(fragment("1"), c.temp))
    normalize(query)
  end


  test "normalize: alias in type/2" do
    query =
      from(x in Post, as: :post)
      |> select([post: p], type(p.visits, p.visits))
      |> normalize()

    assert inspect(query) =~
             "from p0 in Ecto.Query.PlannerTest.Post, as: :post, prefix: \"my_prefix\", select: type(p0.visits, :integer)"
  end

  test "normalize: validate fields in left side of in expressions" do
    query = from(Post, []) |> where([p], p.id in [1, 2, 3])
    normalize(query)

    message = ~r"value `\[1, 2, 3\]` cannot be dumped to type \{:array, :string\}"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(Comment, []) |> where([c], c.text in [1, 2, 3])
      normalize(query)
    end
  end

  test "normalize: validate fields in json_extract_path/2" do
    query = from(Post, []) |> select([p], p.meta["slug"])
    normalize(query)

    query = from(Post, []) |> select([p], p.meta["author"])
    normalize(query)

    query = from(Post, []) |> select([p], p.meta["author"]["name"])
    normalize(query)

    query = from(Post, []) |> select([p], p.metas[0]["slug"])
    normalize(query)

    query = from(Post, []) |> select([p], p.payload["unknown_field"])
    normalize(query)

    query = from(Post, []) |> select([p], p.prefs["unknown_field"])
    normalize(query)

    query = from(p in "posts") |> select([p], p.meta["slug"])
    normalize(query)

    query = from(p  in "posts") |> select([p], p.meta["unknown_field"])
    normalize(query)

    query = from(p  in "posts") |> select([p], p.meta["author"]["unknown_field"])
    normalize(query)

    query = from(p  in "posts") |> select([p], p.metas["not_index"])
    normalize(query)

    query = from(p  in "posts") |> select([p], p.metas["not_index"]["unknown_field"])
    normalize(query)

    assert_raise RuntimeError, "expected field `title` to be an embed or a map, got: `:string`", fn ->
      query = from(Post, []) |> select([p], p.title["foo"])
      normalize(query)
    end

    assert_raise RuntimeError, "field `unknown_field` does not exist in Ecto.Query.PlannerTest.PostMeta", fn ->
      query = from(Post, []) |> select([p], p.meta["unknown_field"])
      normalize(query)
    end

    assert_raise RuntimeError, "field `0` does not exist in Ecto.Query.PlannerTest.PostMeta", fn ->
      query = from(Post, []) |> select([p], p.meta[0])
      normalize(query)
    end

    assert_raise RuntimeError, "field `unknown_field` does not exist in Ecto.Query.PlannerTest.Author", fn ->
      query = from(Post, []) |> select([p], p.meta["author"]["unknown_field"])
      normalize(query)
    end

    assert_raise RuntimeError, "cannot use `not_index` to refer to an item in `embeds_many`", fn ->
      query = from(Post, []) |> select([p], p.metas["not_index"])
      normalize(query)
    end
  end

  test "normalize: flattens and expands right side of in expressions" do
    {query, cast_params, dump_params, _select} = where(Post, [p], p.id in [1, 2, 3]) |> normalize_with_params()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.id() in [1, 2, 3]"
    assert cast_params == []
    assert dump_params == []

    {query, cast_params, dump_params, _select} = where(Post, [p], p.id in [^1, 2, ^3]) |> normalize_with_params()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.id() in [^0, 2, ^1]"
    assert cast_params == [1, 3]
    assert dump_params == [1, 3]

    {query, cast_params, dump_params, _select} = where(Post, [p], p.id in ^[]) |> normalize_with_params()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.id() in ^(0, 0)"
    assert cast_params == []
    assert dump_params == []

    {query, cast_params, dump_params, _select} = where(Post, [p], p.id in ^[1, 2, 3]) |> normalize_with_params()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.id() in ^(0, 3)"
    assert cast_params == [1, 2, 3]
    assert dump_params == [1, 2, 3]

    {query, cast_params, dump_params, _select} = where(Post, [p], p.title == ^"foo" and p.id in ^[1, 2, 3] and
                                                p.title == ^"bar") |> normalize_with_params()
    assert Macro.to_string(hd(query.wheres).expr) ==
           "&0.post_title() == ^0 and &0.id() in ^(1, 3) and &0.post_title() == ^4"
    assert cast_params == ["foo", 1, 2, 3, "bar"]
    assert dump_params == ["foo", 1, 2, 3, "bar"]
  end

  test "normalize: reject empty order by and group by" do
    query = order_by(Post, [], []) |> normalize()
    assert query.order_bys == []

    query = order_by(Post, [], ^[]) |> normalize()
    assert query.order_bys == []

    query = group_by(Post, [], []) |> normalize()
    assert query.group_bys == []
  end

  describe "normalize: CTEs" do
    test "single-level" do
      %{with_ctes: with_expr} =
        Comment
        |> with_cte("cte", as: ^from(c in "comments", select: %{id: c.id, text: c.text}))
        |> normalize()
      %{queries: [{"cte", query}]} = with_expr
      assert query.sources == {{"comments", nil, nil}}
      assert {:%{}, [], [id: _, text: _]} = query.select.expr
      assert  [id: {{:., _, [{:&, _, [0]}, :id]}, _, []},
               text: {{:., [{:type, _} | _], [{:&, _, [0]}, :text]}, _, []}] = query.select.fields

      %{with_ctes: with_expr} =
        Comment
        |> with_cte("cte", as: ^(from(c in Comment, where: c in ^[1, 2, 3])))
        |> normalize()
      %{queries: [{"cte", query}]} = with_expr
      assert query.sources == {{"comments", Comment, nil}}
      assert {:%{}, [], [id: _, text: _] ++ _} = query.select.expr
      assert  [{:id, {{:., _, [{:&, _, [0]}, :id]}, _, []}},
               {:text, {{:., _, [{:&, _, [0]}, :text]}, _, []}},
               _ | _] = query.select.fields
    end

    test "multi-level with select" do
      sensors =
        "sensors"
        |> where(id: ^"id")
        |> select([s], map(s, [:number]))

      # There was a bug where the parameter in select would be reverted
      # to ^0, this test aims to guarantee it remains ^1
      agg_values =
        "values"
        |> with_cte("sensors_cte", as: ^sensors)
        |> join(:inner, [v], s in "sensors_cte")
        |> select([v, s], %{bucket: ^123 + v.number})

      query =
        "agg_values"
        |> with_cte("agg_values", as: ^agg_values)
        |> select([agg_v], agg_v.bucket)

      query = normalize(query)
      [{"agg_values", query}] = query.with_ctes.queries
      assert Macro.to_string(query.select.fields) == "[bucket: ^1 + &0.number()]"
    end

    test "with field select" do
      query =
        "parent"
        |> with_cte("cte", as: ^from(r in "cte", select: r.child))
        |> select([e], [:parent])
        |> normalize()

      [{"cte", query}] = query.with_ctes.queries
      assert Macro.to_string(query.select.fields) == "[child: &0.child()]"
    end
  end

  test "normalize: select" do
    query = from(Post, []) |> normalize()
    assert query.select.expr ==
             {:&, [], [0]}
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links, :prefs, :status, :meta, :metas], 0)

    query = from(Post, []) |> select([p], {p, p.title, "Post"}) |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links, :prefs, :status, :meta, :metas], 0) ++
           [{{:., [type: :string], [{:&, [], [0]}, :post_title]}, [], []}]

    query = from(Post, []) |> select([p], {p.title, p, "Post"}) |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links, :prefs, :status, :meta, :metas], 0) ++
           [{{:., [type: :string], [{:&, [], [0]}, :post_title]}, [], []}]

    query =
      from(Post, [])
      |> join(:inner, [_], c in Comment)
      |> preload([_, c], comments: c)
      |> select([p, _], {p.title, p})
      |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links, :prefs, :status, :meta, :metas], 0) ++
           select_fields([:id, :text, :posted, :uuid, :crazy_comment, :post_id, :crazy_post_id], 1) ++
           [{{:., [type: :string], [{:&, [], [0]}, :post_title]}, [], []}]
  end

  defmacro mymacro(p) do
    quote do
      map(unquote(p), [:id, :title])
    end
  end

  test "normalize: select from macro" do
    query = from(Post, []) |> select([p], map(p, [:id, :title])) |> normalize()
    macro_query = from(Post, []) |> select([p], mymacro(p)) |> normalize()

    assert macro_query.select.fields == query.select.fields
  end

  test "normalize: select with unions" do
    union_query = from(Post, []) |> select([p], %{title: p.title, category: "Post"})
    query = from(Post, []) |> select([p], %{title: p.title, category: "Post"}) |> union(^union_query) |> normalize()

    union_query = query.combinations |> List.first() |> elem(1)
    assert "Post" in query.select.fields
    assert query.select.fields == union_query.select.fields
  end

  test "normalize: select with unions and virtual literal" do
    union_query = from(Post, []) |> select([p], %{title: p.title, temp: true})
    query = from(Post, []) |> select([p], %{title: p.title, temp: false}) |> union(^union_query) |> normalize()

    union_query = query.combinations |> List.first() |> elem(1)
    assert false in query.select.fields
    assert true in union_query.select.fields
  end

  test "normalize: select on schemaless" do
    assert_raise Ecto.QueryError, ~r"need to explicitly pass a :select clause in query", fn ->
      from("posts", []) |> normalize()
    end
  end

  test "normalize: select with struct/2" do
    assert_raise Ecto.QueryError, ~r"struct/2 in select expects a source with a schema", fn ->
      "posts" |> select([p], struct(p, [:id, :title])) |> normalize()
    end

    query = Post |> select([p], struct(p, [:id, :title])) |> normalize()
    assert query.select.expr == {:&, [], [0]}
    assert query.select.fields == select_fields([:id, :post_title], 0)

    query = Post |> select([p], {struct(p, [:id, :title]), p.title}) |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title], 0) ++
           [{{:., [type: :string], [{:&, [], [0]}, :post_title]}, [], []}]

    query =
      Post
      |> join(:inner, [_], c in Comment)
      |> select([p, c], {p, struct(c, [:id, :text])})
      |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links, :prefs, :status, :meta, :metas], 0) ++
           select_fields([:id, :text], 1)
  end

  test "normalize: select with struct/2 on assoc" do
    query =
      Post
      |> join(:inner, [_], c in Comment)
      |> select([p, c], struct(p, [:id, :title, comments: [:id, :text]]))
      |> preload([p, c], comments: c)
      |> normalize()
    assert query.select.expr == {:&, [], [0]}
    assert query.select.fields ==
           select_fields([:id, :post_title], 0) ++
           select_fields([:id, :text], 1)

    query =
      Post
      |> join(:inner, [_], c in Comment)
      |> select([p, c], struct(p, [:id, :title, comments: [:id, :text, post: :id], extra_comments: :id]))
      |> preload([p, c], comments: {c, post: p}, extra_comments: c)
      |> normalize()
    assert query.select.expr == {:&, [], [0]}
    assert query.select.fields ==
           select_fields([:id, :post_title], 0) ++
           select_fields([:id, :text], 1) ++
           select_fields([:id], 0) ++
           select_fields([:id], 1)
  end

  test "normalize: select with struct/2 on fragment" do
    assert_raise Ecto.QueryError, ~r"it is not possible to return a struct subset of a fragment", fn ->
      Post
      |> join(:inner, [_], c in fragment("comments"))
      |> select([_, c], struct(c, [:id]))
      |> normalize()
    end
  end

  test "normalize: select with map/2" do
    query = Post |> select([p], map(p, [:id, :title])) |> normalize()
    assert query.select.expr == {:&, [], [0]}
    assert query.select.fields == select_fields([:id, :post_title], 0)

    query = Post |> select([p], {map(p, [:id, :title]), p.title}) |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title], 0) ++
           [{{:., [type: :string], [{:&, [], [0]}, :post_title]}, [], []}]

    query =
      Post
      |> join(:inner, [_], c in Comment)
      |> select([p, c], {p, map(c, [:id, :text])})
      |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links, :prefs, :status, :meta, :metas], 0) ++
           select_fields([:id, :text], 1)
  end

  test "normalize: select with map/2 on assoc" do
    query =
      Post
      |> join(:inner, [_], c in Comment)
      |> select([p, c], map(p, [:id, :title, comments: [:id, :text]]))
      |> preload([p, c], comments: c)
      |> normalize()
    assert query.select.expr == {:&, [], [0]}
    assert query.select.fields ==
           select_fields([:id, :post_title], 0) ++
           select_fields([:id, :text], 1)

    query =
      Post
      |> join(:inner, [_], c in Comment)
      |> select([p, c], map(p, [:id, :title, comments: [:id, :text, post: :id], extra_comments: :id]))
      |> preload([p, c], comments: {c, post: p}, extra_comments: c)
      |> normalize()
    assert query.select.expr == {:&, [], [0]}
    assert query.select.fields ==
           select_fields([:id, :post_title], 0) ++
           select_fields([:id, :text], 1) ++
            select_fields([:id], 0) ++
           select_fields([:id], 1)
  end

  test "normalize: select with map/2 on fragment" do
    query =
      Post
      |> join(:inner, [_], f in fragment("select 1 as a, 2 as b"))
      |> select([_, f], map(f, [:a, :b]))
      |> normalize()

    assert query.select.expr == {:&, [], [1]}

    assert query.select.fields ==
             select_fields([:a], 1) ++
               select_fields([:b], 1)
  end

  test "normalize: select with :%{}" do
    query = Post |> select([p], %{p | title: "foo"}) |> normalize()
    assert query.select.expr == {:%{}, [], [{:|, [], [{:&, [], [0]}, [title: "foo"]]}]}
    assert query.select.fields ==
      select_fields([:id, :text, :code, :posted, :visits, :links, :prefs, :status, :meta, :metas], 0)

    query = Post |> select([p], {%{p | title: "foo"}, p.title}) |> normalize()
    assert query.select.fields ==
           select_fields([:id, :text, :code, :posted, :visits, :links, :prefs, :status, :meta, :metas], 0) ++
           [{{:., [type: :string], [{:&, [], [0]}, :post_title]}, [], []}]

    query =
      Post
      |> join(:inner, [_], c in Comment)
      |> select([p, c], {p, %{c | text: "bar"}})
      |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links, :prefs, :status, :meta, :metas], 0) ++
           select_fields([:id, :posted, :uuid, :crazy_comment, :post_id, :crazy_post_id], 1)
  end

  test "normalize: select with subquery" do
    subquery =
      Comment
      |> where([c], c.post_id == parent_as(:post).id)
      |> select(count())

    query =
      from(Post, as: :post)
      |> select([p], %{title: p.title, comment_count: subquery(subquery)})
      |> normalize()

    assert {:%{}, [],
            [
              title: {{:., [type: :string], [{:&, [], [0]}, :post_title]}, [], []},
              comment_count: %Ecto.SubQuery{}
            ]} = query.select.expr

    assert [
             {{:., [type: :string], [{:&, [], [0]}, :post_title]}, [], []},
             %Ecto.SubQuery{}
           ] = query.select.fields
  end

  test "normalize: windows" do
    assert_raise Ecto.QueryError, ~r"unknown window :v given to over/2", fn ->
      Comment
      |> windows([c], w: [partition_by: c.id])
      |> select([c], count(c.id) |> over(:v))
      |> normalize()
    end
  end

  test "normalize: preload errors" do
    message = ~r"the binding used in `from` must be selected in `select` when using `preload`"
    assert_raise Ecto.QueryError, message, fn ->
      Post |> preload(:hello) |> select([p], p.title) |> normalize
    end

    message = ~r"invalid query has specified more bindings than"
    assert_raise Ecto.QueryError, message, fn ->
      Post |> preload([p, c], comments: c) |> normalize
    end
  end

  test "normalize: preload assoc merges"  do
    {_, _, _, select} =
      from(p in Post)
      |> join(:inner, [p], c in assoc(p, :comments))
      |> join(:inner, [_, c], cp in assoc(c, :comment_posts))
      |> join(:inner, [_, c], ip in assoc(c, :post))
      |> preload([_, c, cp, _], comments: {c, comment_posts: cp})
      |> preload([_, c, _, ip], comments: {c, post: ip})
      |> normalize_with_params()

    assert select.assocs == [comments: {1, [comment_posts: {2, []}, post: {3, []}]}]
  end

  test "normalize: preload assoc errors" do
    message = ~r"field `Ecto.Query.PlannerTest.Post.not_field` in preload is not an association"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(p in Post, join: c in assoc(p, :comments), preload: [not_field: c])
      normalize(query)
    end

    message = ~r"requires an inner, left or lateral join, got right join"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(p in Post, right_join: c in assoc(p, :comments), preload: [comments: c])
      normalize(query)
    end
  end

  test "normalize: fragments do not support preloads" do
    query = from p in Post, join: c in fragment("..."), preload: [comments: c]
    assert_raise Ecto.QueryError, ~r/can only preload sources with a schema/, fn ->
      normalize(query)
    end
  end

  test "normalize: all does not allow updates" do
    message = ~r"`all` does not allow `update` expressions"
    assert_raise Ecto.QueryError, message, fn ->
      from(p in Post, update: [set: [name: "foo"]]) |> normalize(:all)
    end
  end

  test "normalize: update all only allow filters and checks updates" do
    message = ~r"`update_all` requires at least one field to be updated"
    assert_raise Ecto.QueryError, message, fn ->
      from(p in Post, select: p, update: []) |> normalize(:update_all)
    end

    message = ~r"duplicate field `title` for `update_all`"
    assert_raise Ecto.QueryError, message, fn ->
      from(p in Post, select: p, update: [set: [title: "foo", title: "bar"]])
      |> normalize(:update_all)
    end

    message = ~r"`update_all` allows only `with_cte`, `where` and `join` expressions"
    assert_raise Ecto.QueryError, message, fn ->
      from(p in Post, order_by: p.title, update: [set: [title: "foo"]]) |> normalize(:update_all)
    end
  end

  test "normalize: delete all only allow filters and forbids updates" do
    message = ~r"`delete_all` does not allow `update` expressions"
    assert_raise Ecto.QueryError, message, fn ->
      from(p in Post, update: [set: [name: "foo"]]) |> normalize(:delete_all)
    end

    message = ~r"`delete_all` allows only `with_cte`, `where` and `join` expressions"
    assert_raise Ecto.QueryError, message, fn ->
      from(p in Post, order_by: p.title) |> normalize(:delete_all)
    end
  end

  describe "normalize: subqueries in boolean expressions" do
    test "replaces {:subquery, index} with an Ecto.SubQuery struct" do
      subquery = from(p in Post, select: p.visits)

      %{wheres: [where]} =
        from(p in Post, where: p.visits in subquery(subquery))
        |> normalize()

      assert {:in, _, [_, %Ecto.SubQuery{}] } = where.expr

      %{wheres: [where]} =
        from(p in Post, where: p.visits >= all(subquery))
        |> normalize()

      assert {:>=, _, [_, {:all, _, [%Ecto.SubQuery{}] }]} = where.expr

      %{wheres: [where]} =
        from(p in Post, where: exists(subquery))
        |> normalize()

      assert {:exists, _, [%Ecto.SubQuery{}]} = where.expr

      avg_visits = from(p in Post, select: avg(p.visits))

      %{wheres: [where]} =
        from(p in Post, where: p.visits > subquery(avg_visits))
        |> normalize()

      assert {:>, _, [_, %Ecto.SubQuery{}]} = where.expr
    end

    test "raises a runtime error if more than 1 field is selected" do
      s = from(p in Post, select: [p.visits, p.id])

      assert_raise Ecto.QueryError, fn ->
        from(p in Post, where: p.id in subquery(s))
        |> normalize()
      end

      assert_raise Ecto.QueryError, fn ->
        from(p in Post, where: p.id > any(s))
        |> normalize()
      end

      assert_raise Ecto.QueryError, fn ->
        from(p in Post, where: p.id > all(s))
        |> normalize()
      end
    end
  end

  describe "filter" do
    test "with aggregate" do
      from(c in Comment,
        group_by: c.post_id,
        select: %{
          not_aaaa_comments_count: count(c.text) |> filter(c.text != "aaaa")
        }
      )
      |> normalize()
    end

    test "with fragment" do
      from(c in Comment,
        group_by: c.post_id,
        select: %{
          not_aaaa_comments_count: fragment("count(?)", c.text) |> filter(c.text != "aaaa")
        }
      )
      |> normalize()
    end
  end
end
