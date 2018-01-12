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
      field :temp, :string, virtual: true
      field :posted, :naive_datetime
      field :uuid, :binary_id
      belongs_to :post, Ecto.Query.PlannerTest.Post
      has_many :post_comments, through: [:post, :comments]
    end
  end

  defmodule Post do
    use Ecto.Schema

    @primary_key {:id, Custom.Permalink, []}
    schema "posts" do
      field :title, :string, source: :post_title
      field :text, :string
      field :code, :binary
      field :posted, :naive_datetime
      field :visits, :integer
      field :links, {:array, Custom.Permalink}
      has_many :comments, Ecto.Query.PlannerTest.Comment
      has_many :extra_comments, Ecto.Query.PlannerTest.Comment
    end
  end

  defp prepare(query, operation \\ :all) do
    Planner.prepare(query, operation, Ecto.TestAdapter, 0)
  end

  defp normalize(query, operation \\ :all) do
    normalize_with_params(query, operation) |> elem(0)
  end

  defp normalize_with_params(query, operation \\ :all) do
    {query, params, _key} = prepare(query, operation)
    {query, _} =
      query
      |> Planner.returning(operation == :all)
      |> Planner.normalize(operation, Ecto.TestAdapter, 0)
    {query, params}
  end

  defp select_fields(fields, ix) do
    for field <- fields do
      {{:., [], [{:&, [], [ix]}, field]}, [], []}
    end
  end

  test "prepare: merges all parameters" do
    query =
      from p in Post,
        select: {p.title, ^"0"},
        join: c in Comment,
        on: c.text == ^"1",
        left_join: d in assoc(p, :comments),
        where: p.title == ^"2",
        group_by: p.title == ^"3",
        having: p.title == ^"4",
        order_by: [asc: fragment("?", ^"5")],
        limit: ^6,
        offset: ^7

    {_query, params, _key} = prepare(query)
    assert params == ["0", "1", "2", "3", "4", "5", 6, 7]
  end

  test "prepare: checks from" do
    assert_raise Ecto.QueryError, ~r"query must have a from expression", fn ->
      prepare(%Ecto.Query{})
    end
  end

  test "prepare: casts values" do
    {_query, params, _key} = prepare(Post |> where([p], p.id == ^"1"))
    assert params == [1]

    exception = assert_raise Ecto.Query.CastError, fn ->
      prepare(Post |> where([p], p.title == ^1))
    end

    assert Exception.message(exception) =~ "value `1` in `where` cannot be cast to type :string"
    assert Exception.message(exception) =~ "where: p.title == ^1"
  end

  test "prepare: raises readable error on dynamic expressions/keyword lists" do
    dynamic = dynamic([p], p.id == ^"1")
    {_query, params, _key} = prepare(Post |> where([p], ^dynamic))
    assert params == [1]

    assert_raise Ecto.QueryError, ~r/dynamic expressions can only be interpolated/, fn ->
      prepare(Post |> where([p], p.title == ^dynamic))
    end

    assert_raise Ecto.QueryError, ~r/keyword lists can only be interpolated/, fn ->
      prepare(Post |> where([p], p.title == ^[foo: 1]))
    end
  end

  test "prepare: casts and dumps custom types" do
    permalink = "1-hello-world"
    {_query, params, _key} = prepare(Post |> where([p], p.id == ^permalink))
    assert params == [1]
  end

  test "prepare: casts and dumps binary ids" do
    uuid = "00010203-0405-4607-8809-0a0b0c0d0e0f"
    {_query, params, _key} = prepare(Comment |> where([c], c.uuid == ^uuid))
    assert params == [<<0, 1, 2, 3, 4, 5, 70, 7, 136, 9, 10, 11, 12, 13, 14, 15>>]

    assert_raise Ecto.Query.CastError,
                 ~r/`"00010203-0405-4607-8809"` cannot be dumped to type :binary_id/, fn ->
      uuid = "00010203-0405-4607-8809"
      prepare(Comment |> where([c], c.uuid == ^uuid))
    end
  end

  test "prepare: casts and dumps custom types in left side of in-expressions" do
    permalink = "1-hello-world"
    {_query, params, _key} = prepare(Post |> where([p], ^permalink in p.links))
    assert params == [1]

    message = ~r"value `\"1-hello-world\"` in `where` expected to be part of an array but matched type is :string"
    assert_raise Ecto.Query.CastError, message, fn ->
      prepare(Post |> where([p], ^permalink in p.text))
    end
  end

  test "prepare: casts and dumps custom types in right side of in-expressions" do
    datetime = ~N[2015-01-07 21:18:13.0]
    {_query, params, _key} = prepare(Comment |> where([c], c.posted in ^[datetime]))
    assert params == [{{2015, 1, 7}, {21, 18, 13, 0}}]

    permalink = "1-hello-world"
    {_query, params, _key} = prepare(Post |> where([p], p.id in ^[permalink]))
    assert params == [1]

    datetime = ~N[2015-01-07 21:18:13.0]
    {_query, params, _key} = prepare(Comment |> where([c], c.posted in [^datetime]))
    assert params == [{{2015, 1, 7}, {21, 18, 13, 0}}]

    permalink = "1-hello-world"
    {_query, params, _key} = prepare(Post |> where([p], p.id in [^permalink]))
    assert params == [1]

    {_query, params, _key} = prepare(Post |> where([p], p.code in [^"abcd"]))
    assert params == ["abcd"]

    {_query, params, _key} = prepare(Post |> where([p], p.code in ^["abcd"]))
    assert params == ["abcd"]
  end

  test "prepare: casts values on update_all" do
    {_query, params, _key} = prepare(Post |> update([p], set: [id: ^"1"]), :update_all)
    assert params == [1]

    {_query, params, _key} = prepare(Post |> update([p], set: [title: ^nil]), :update_all)
    assert params == [nil]

    {_query, params, _key} = prepare(Post |> update([p], set: [title: nil]), :update_all)
    assert params == []
  end

  test "prepare: joins" do
    query = from(p in Post, join: c in "comments") |> prepare |> elem(0)
    assert hd(query.joins).source == {"comments", nil}

    query = from(p in Post, join: c in Comment) |> prepare |> elem(0)
    assert hd(query.joins).source == {"comments", Comment}

    query = from(p in Post, join: c in {"post_comments", Comment}) |> prepare |> elem(0)
    assert hd(query.joins).source == {"post_comments", Comment}
  end

  test "prepare: joins associations" do
    query = from(p in Post, join: assoc(p, :comments)) |> prepare |> elem(0)
    assert %JoinExpr{on: on, source: source, assoc: nil, qual: :inner} = hd(query.joins)
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id()"

    query = from(p in Post, left_join: assoc(p, :comments)) |> prepare |> elem(0)
    assert %JoinExpr{on: on, source: source, assoc: nil, qual: :left} = hd(query.joins)
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id()"

    query = from(p in Post, left_join: c in assoc(p, :comments), on: p.title == c.text) |> prepare |> elem(0)
    assert %JoinExpr{on: on, source: source, assoc: nil, qual: :left} = hd(query.joins)
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id() and &0.title() == &1.text()"
  end

  test "prepare: nested joins associations" do
    query = from(c in Comment, left_join: assoc(c, :post_comments)) |> prepare |> elem(0)
    assert {{"comments", _}, {"comments", _}, {"posts", _}} = query.sources
    assert [join1, join2] = query.joins
    assert Enum.map(query.joins, & &1.ix) == [2, 1]
    assert Macro.to_string(join1.on.expr) == "&2.id() == &0.post_id()"
    assert Macro.to_string(join2.on.expr) == "&1.post_id() == &2.id()"

    query = from(p in Comment, left_join: assoc(p, :post),
                               left_join: assoc(p, :post_comments)) |> prepare |> elem(0)
    assert {{"comments", _}, {"posts", _}, {"comments", _}, {"posts", _}} = query.sources
    assert [join1, join2, join3] = query.joins
    assert Enum.map(query.joins, & &1.ix) == [1, 3, 2]
    assert Macro.to_string(join1.on.expr) == "&1.id() == &0.post_id()"
    assert Macro.to_string(join2.on.expr) == "&3.id() == &0.post_id()"
    assert Macro.to_string(join3.on.expr) == "&2.post_id() == &3.id()"

    query = from(p in Comment, left_join: assoc(p, :post_comments),
                               left_join: assoc(p, :post)) |> prepare |> elem(0)
    assert {{"comments", _}, {"comments", _}, {"posts", _}, {"posts", _}} = query.sources
    assert [join1, join2, join3] = query.joins
    assert Enum.map(query.joins, & &1.ix) == [3, 1, 2]
    assert Macro.to_string(join1.on.expr) == "&3.id() == &0.post_id()"
    assert Macro.to_string(join2.on.expr) == "&1.post_id() == &3.id()"
    assert Macro.to_string(join3.on.expr) == "&2.id() == &0.post_id()"
  end

  test "prepare: cannot associate without schema" do
    query   = from(p in "posts", join: assoc(p, :comments))
    message = ~r"cannot perform association join on \"posts\" because it does not have a schema"

    assert_raise Ecto.QueryError, message, fn ->
      prepare(query)
    end
  end

  test "prepare: requires an association field" do
    query = from(p in Post, join: assoc(p, :title))

    assert_raise Ecto.QueryError, ~r"could not find association `title`", fn ->
      prepare(query)
    end
  end

  test "prepare: generates a cache key" do
    {_query, _params, key} = prepare(from(Post, []))
    assert key == [:all, 0, {"posts", Post, 27727487}]

    query = from(p in Post, select: 1, lock: "foo", where: is_nil(nil), or_where: is_nil(nil),
                            join: c in Comment, preload: :comments)
    {_query, _params, key} = prepare(%{query | prefix: "foo"})
    assert key == [:all, 0,
                   {:lock, "foo"},
                   {:prefix, "foo"},
                   {:where, [{:and, {:is_nil, [], [nil]}}, {:or, {:is_nil, [], [nil]}}]},
                   {:join, [{:inner, {"comments", Comment, 6996781}, true}]},
                   {"posts", Post, 27727487},
                   {:select, 1}]
  end

  test "prepare: generates a cache key for in based on the adapter" do
    query = from(p in Post, where: p.id in ^[1, 2, 3])

    {_query, _params, key} = Planner.prepare(query, :all, Ecto.TestAdapter, 0)
    assert key == :nocache

    {_query, _params, key} = Planner.prepare(query, :all, Ecto.Adapters.Postgres, 0)
    assert key != :nocache
  end

  test "normalize: tagged types" do
    {query, params} = from(Post, []) |> select([p], type(^"1", :integer))
                                     |> normalize_with_params
    assert query.select.expr ==
           %Ecto.Query.Tagged{type: :integer, value: {:^, [], [0]}, tag: :integer}
    assert params == [1]

    {query, params} = from(Post, []) |> select([p], type(^"1", Custom.Permalink))
                                     |> normalize_with_params
    assert query.select.expr ==
           %Ecto.Query.Tagged{type: :id, value: {:^, [], [0]}, tag: Custom.Permalink}
    assert params == [1]

    {query, params} = from(Post, []) |> select([p], type(^"1", p.visits))
                                     |> normalize_with_params
    assert query.select.expr ==
           %Ecto.Query.Tagged{type: :integer, value: {:^, [], [0]}, tag: :integer}
    assert params == [1]

    assert_raise Ecto.Query.CastError, ~r/value `"1"` in `select` cannot be cast to type Ecto.UUID/, fn ->
      from(Post, []) |> select([p], type(^"1", Ecto.UUID)) |> normalize
    end
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

    message = ~r"field `temp` in `select` is a virtual field in schema Ecto.Query.PlannerTest.Comment"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(Comment, []) |> select([c], c.temp)
      normalize(query)
    end
  end

  test "normalize: validate fields in left side of in expressions" do
    query = from(Post, []) |> where([p], p.id in [1, 2, 3])
    normalize(query)

    message = ~r"value `1` cannot be dumped to type :string"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(Comment, []) |> where([c], c.text in [1, 2, 3])
      normalize(query)
    end
  end

  test "normalize: flattens and expands right side of in expressions" do
    {query, params} = where(Post, [p], p.id in [1, 2, 3]) |> normalize_with_params()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.id() in [1, 2, 3]"
    assert params == []

    {query, params} = where(Post, [p], p.id in [^1, 2, ^3]) |> normalize_with_params()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.id() in [^0, 2, ^1]"
    assert params == [1, 3]

    {query, params} = where(Post, [p], p.id in ^[]) |> normalize_with_params()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.id() in ^(0, 0)"
    assert params == []

    {query, params} = where(Post, [p], p.id in ^[1, 2, 3]) |> normalize_with_params()
    assert Macro.to_string(hd(query.wheres).expr) == "&0.id() in ^(0, 3)"
    assert params == [1, 2, 3]

    {query, params} = where(Post, [p], p.title == ^"foo" and p.id in ^[1, 2, 3] and
                                       p.title == ^"bar") |> normalize_with_params()
    assert Macro.to_string(hd(query.wheres).expr) ==
           "&0.post_title() == ^0 and &0.id() in ^(1, 3) and &0.post_title() == ^4"
    assert params == ["foo", 1, 2, 3, "bar"]
  end

  test "normalize: reject empty order by and group by" do
    query = order_by(Post, [], []) |> normalize()
    assert query.order_bys == []

    query = order_by(Post, [], ^[]) |> normalize()
    assert query.order_bys == []

    query = group_by(Post, [], []) |> normalize()
    assert query.group_bys == []
  end

  test "normalize: select" do
    query = from(Post, []) |> normalize()
    assert query.select.expr ==
             {:&, [], [0]}
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links], 0)

    query = from(Post, []) |> select([p], {p, p.title}) |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links], 0) ++
           [{{:., [], [{:&, [], [0]}, :post_title]}, [], []}]

    query = from(Post, []) |> select([p], {p.title, p}) |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links], 0) ++
           [{{:., [], [{:&, [], [0]}, :post_title]}, [], []}]

    query =
      from(Post, [])
      |> join(:inner, [_], c in Comment)
      |> preload([_, c], comments: c)
      |> select([p, _], {p.title, p})
      |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links], 0) ++
           select_fields([:id, :text, :posted, :uuid, :post_id], 1) ++
           [{{:., [], [{:&, [], [0]}, :post_title]}, [], []}]
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
           [{{:., [], [{:&, [], [0]}, :post_title]}, [], []}]

    query =
      Post
      |> join(:inner, [_], c in Comment)
      |> select([p, c], {p, struct(c, [:id, :text])})
      |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links], 0) ++
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
           select_fields([:id], 1) ++
           select_fields([:id, :text], 1) ++
           select_fields([:id], 0)
  end

  test "normalize: select with map/2" do
    query = Post |> select([p], map(p, [:id, :title])) |> normalize()
    assert query.select.expr == {:&, [], [0]}
    assert query.select.fields == select_fields([:id, :post_title], 0)

    query = Post |> select([p], {map(p, [:id, :title]), p.title}) |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title], 0) ++
           [{{:., [], [{:&, [], [0]}, :post_title]}, [], []}]

    query =
      Post
      |> join(:inner, [_], c in Comment)
      |> select([p, c], {p, map(c, [:id, :text])})
      |> normalize()
    assert query.select.fields ==
           select_fields([:id, :post_title, :text, :code, :posted, :visits, :links], 0) ++
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
           select_fields([:id], 1) ++
           select_fields([:id, :text], 1) ++
           select_fields([:id], 0)
  end

  test "normalize: preload" do
    message = ~r"the binding used in `from` must be selected in `select` when using `preload`"
    assert_raise Ecto.QueryError, message, fn ->
      Post |> preload(:hello) |> select([p], p.title) |> normalize
    end

    message = ~r"cannot prepare query because it has specified more bindings than"
    assert_raise Ecto.QueryError, message, fn ->
      Post |> preload([p, c], comments: c) |> normalize
    end
  end

  test "normalize: preload assoc" do
    query = from(p in Post, join: c in assoc(p, :comments), preload: [comments: c])
    normalize(query)

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

    message = ~r"`update_all` allows only `where` and `join` expressions"
    assert_raise Ecto.QueryError, message, fn ->
      from(p in Post, order_by: p.title, update: [set: [title: "foo"]]) |> normalize(:update_all)
    end
  end

  test "normalize: delete all only allow filters and forbids updates" do
    message = ~r"`delete_all` does not allow `update` expressions"
    assert_raise Ecto.QueryError, message, fn ->
      from(p in Post, update: [set: [name: "foo"]]) |> normalize(:delete_all)
    end

    message = ~r"`delete_all` allows only `where` and `join` expressions"
    assert_raise Ecto.QueryError, message, fn ->
      from(p in Post, order_by: p.title) |> normalize(:delete_all)
    end
  end
end
