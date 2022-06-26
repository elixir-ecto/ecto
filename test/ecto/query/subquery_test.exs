Code.require_file "../../../integration_test/support/types.exs", __DIR__

defmodule Ecto.Query.SubqueryTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Query.Planner
  alias Ecto.Query.JoinExpr

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field :text, :string
      field :updated_at, :utc_datetime_usec
      field :temp, :string, virtual: true
      belongs_to :post, Ecto.Query.SubqueryTest.Post, type: CustomPermalink
      has_many :post_comments, through: [:post, :comments]
    end
  end

  defmodule Post do
    use Ecto.Schema

    @primary_key {:id, CustomPermalink, []}
    @schema_prefix "my_prefix"
    schema "posts" do
      field :title, :string, source: :post_title
      field :text, :string
      field :comment_updated_at, :utc_datetime_usec, virtual: true
      has_many :comments, Ecto.Query.SubqueryTest.Comment
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

    {query, _} =
      query
      |> Planner.ensure_select(operation == :all)
      |> Planner.normalize(operation, Ecto.TestAdapter, 0)

    {query, cast_params, dump_params}
  end

  defp select_fields(fields, ix) do
    for field <- fields do
      {{:., [], [{:&, [], [ix]}, field]}, [], []}
    end
  end

  describe "plan: source subqueries" do
    test "in from" do
      {query, cast_params, dump_params, key} = plan(from(subquery(Post), []))
      assert %{query: %Ecto.Query{}, params: []} = query.from.source
      assert cast_params == []
      assert dump_params == []
      assert key == [:all, {:from, [:all, {:from, {"posts", Ecto.Query.SubqueryTest.Post, 52805476, "my_prefix"}, []}], []}]
    end

    test "in join" do
      posts = from(p in Post, where: p.title == ^"hello")
      query = from(c in Comment, join: p in subquery(posts), on: c.post_id == p.id)
      {query, cast_params, dump_params, key} = plan(query)
      assert {"comments", Comment} = query.from.source
      assert [%{source: %{query: %Ecto.Query{}, params: [{"hello", "hello"}]}}] = query.joins
      assert cast_params == ["hello"]
      assert dump_params == ["hello"]
      assert [:all, {:join, [{:inner, [:all | _], _, []}]}, {:from, {"comments", _, _, _}, []}] = key
    end

    test "with association joins" do
      {query, _, _, _} = plan(from(p in subquery(Post), join: c in assoc(p, :comments)))
      assert [%{source: {"comments", Comment}}] = query.joins

      message = ~r/can only perform association joins on subqueries that return a source with schema in select/
      assert_raise Ecto.QueryError, message, fn ->
        plan(from(p in subquery(from p in Post, select: p.title), join: c in assoc(p, :comments)))
      end
    end

    test "with literals" do
      subquery = select(Post, [p], %{t: p.title, l: "literal"})
      query = normalize(from(p in subquery(subquery), select: %{x: p.t, y: p.l, z: "otherliteral"}))

      assert query.select.fields == [
        {{:., [type: :string], [{:&, [], [0]}, :t]}, [], []},
        {{:., [type: :binary], [{:&, [], [0]}, :l]}, [], []}
      ]

      assert [{:t, _}, {:l, "literal"}] = query.from.source.query.select.fields
    end

    test "invalid values" do
      message = "atoms, structs, maps, lists, tuples and sources are not allowed as map values in subquery"

      assert_raise Ecto.SubQueryError, ~r/#{message}/, fn ->
        query = select(Post, [p], %{t: p.title, l: :literal})
        plan(from(subquery(query), []))
      end

      assert_raise Ecto.SubQueryError, ~r/#{message}/, fn ->
        query = select(Post, [p], %{t: p.title, l: []})
        plan(from(subquery(query), []))
      end

      assert_raise Ecto.SubQueryError, ~r/#{message}/, fn ->
        query = select(Post, [p], %{t: p.title, l: %{}})
        plan(from(subquery(query), []))
      end

      assert_raise Ecto.SubQueryError, ~r/#{message}/, fn ->
        query = select(Post, [p], %{t: p.title, l: {1, 2, 3}})
        plan(from(subquery(query), []))
      end

      assert_raise Ecto.SubQueryError, ~r/#{message}/, fn ->
        query = select(Post, [p], %{t: p.title, l: p})
        plan(from(subquery(query), []))
      end

      assert_raise Ecto.SubQueryError, ~r/#{message}/, fn ->
        query = select(Post, [p], %{t: p.title, l: %Post{}})
        plan(from(subquery(query), []))
      end
    end

    test "with map updates in select can be used with assoc" do
      query =
        Post
        |> select([post], %{post | title: ^"hello"})
        |> subquery()
        |> join(:left, [subquery_post], comment in assoc(subquery_post, :comments))
        |> plan()
        |> elem(0)

      assert %JoinExpr{on: on, source: source, assoc: nil, qual: :left} = hd(query.joins)
      assert source == {"comments", Comment}
      assert Macro.to_string(on.expr) == "&1.post_id() == &0.id()"
    end

    test "do not support preloads" do
      query = from p in Post, join: c in assoc(p, :comments), preload: [comments: c]
      assert_raise Ecto.SubQueryError, ~r/cannot preload associations in subquery/, fn ->
        plan(from(subquery(query), []))
      end
    end

    test "allows type casting from subquery types" do
      query = subquery(from p in Post, join: c in assoc(p, :comments),
                                       select: %{id: p.id, title: p.title})

      permalink = "1-hello-world"
      {_query, cast_params, dump_params, _key} = plan(query |> where([p], p.id == ^permalink))
      assert cast_params == [1]
      assert dump_params == [1]

      assert_raise Ecto.Query.CastError, ~r/value `1` in `where` cannot be cast to type :string in query/, fn ->
        plan(query |> where([p], p.title == ^1))
      end

      assert_raise Ecto.QueryError, ~r/field `unknown` does not exist in subquery in query/, fn ->
        plan(query |> where([p], p.unknown == ^1))
      end
    end

    test "wraps subquery errors" do
      exception = assert_raise Ecto.SubQueryError, fn ->
        query = Post |> where([p], p.title == ^1)
        plan(from(subquery(query), []))
      end

      assert %Ecto.Query.CastError{} = exception.exception
      assert Exception.message(exception) =~ "the following exception happened when compiling a subquery."
      assert Exception.message(exception) =~ "value `1` in `where` cannot be cast to type :string"
      assert Exception.message(exception) =~ "where: p0.title == ^1"
      assert Exception.message(exception) =~ "from p0 in subquery(from p0 in Ecto.Query.SubqueryTest.Post"
    end

    test "prefix" do
      {query, _, _, _} = from(subquery(Comment), select: 1) |> plan()
      assert {%{query: %{sources: {{"comments", Comment, nil}}}}} = query.sources

      {query, _, _, _} = from(subquery(Comment), select: 1) |> Map.put(:prefix, "global") |> plan()
      assert {%{query: %{sources: {{"comments", Comment, "global"}}}}} = query.sources

      {query, _, _, _} = from(subquery(Comment, prefix: "sub"), select: 1) |> Map.put(:prefix, "global") |> plan()
      assert {%{query: %{sources: {{"comments", Comment, "sub"}}}}} = query.sources

      {query, _, _, _} = from(subquery(Comment, prefix: "sub"), prefix: "local", select: 1) |> Map.put(:prefix, "global") |> plan()
      assert {%{query: %{sources: {{"comments", Comment, "local"}}}}} = query.sources

      {query, _, _, _} = from(subquery(Post), select: 1) |> plan()
      assert {%{query: %{sources: {{"posts", Post, "my_prefix"}}}}} = query.sources

      {query, _, _, _} = from(subquery(Post), select: 1) |> Map.put(:prefix, "global") |> plan()
      assert {%{query: %{sources: {{"posts", Post, "my_prefix"}}}}} = query.sources

      {query, _, _, _} = from(subquery(Post, prefix: "sub"), select: 1) |> Map.put(:prefix, "global") |> plan()
      assert {%{query: %{sources: {{"posts", Post, "my_prefix"}}}}} = query.sources

      {query, _, _, _} = from(subquery(Post, prefix: "sub"), prefix: "local", select: 1) |> Map.put(:prefix, "global") |> plan()
      assert {%{query: %{sources: {{"posts", Post, "my_prefix"}}}}} = query.sources
    end
  end

  describe "plan: subqueries select" do
    test "supports implicit select" do
      query = plan(from(subquery(Post), [])) |> elem(0)
      assert "%{id: &0.id(), title: &0.title(), text: &0.text()}" = Macro.to_string(query.from.source.query.select.expr)
    end

    test "supports field selector" do
      query = from p in "posts", select: p.text
      query = plan(from(subquery(query), [])) |> elem(0)
      assert "%{text: &0.text()}" =
             Macro.to_string(query.from.source.query.select.expr)

      query = from p in Post, select: p.text
      query = plan(from(subquery(query), [])) |> elem(0)
      assert "%{text: &0.text()}" =
             Macro.to_string(query.from.source.query.select.expr)
    end

    test "supports maps" do
      query = from p in Post, select: %{text: p.text}
      query = plan(from(subquery(query), [])) |> elem(0)
      assert "%{text: &0.text()}" =
             Macro.to_string(query.from.source.query.select.expr)
    end

    test "supports structs" do
      query = from p in Post, select: %Post{text: p.text}
      query = plan(from(subquery(query), [])) |> elem(0)
      assert "%{text: &0.text()}" =
             Macro.to_string(query.from.source.query.select.expr)
    end

    test "supports update in maps" do
      query = from p in Post, select: %{p | text: p.title}
      query = plan(from(subquery(query), [])) |> elem(0)
      assert "%{id: &0.id(), title: &0.title(), text: &0.title()}" =
             Macro.to_string(query.from.source.query.select.expr)
    end

    test "supports merge" do
      query = from p in Post, select: merge(p, %{text: p.title})
      query = plan(from(subquery(query), [])) |> elem(0)
      assert "%{id: &0.id(), title: &0.title(), text: &0.title()}" =
             Macro.to_string(query.from.source.query.select.expr)

      query = from p in Post, select: merge(%{}, %{})
      query = plan(from(subquery(query), [])) |> elem(0)
      assert "%{}" = Macro.to_string(query.from.source.query.select.expr)
    end

    test "merging fields from other sources or schemas retains the field type" do
      query = from p in Post, join: c in assoc(p, :comments), select: merge(p, %{comment_updated_at: c.updated_at})
      subquery = normalize(from(subquery(query), []))
      %{select: {:source, _source, _prefix, types}} = subquery.sources |> elem(0)
      assert types[:comment_updated_at] == :utc_datetime_usec
    end

    test "requires atom keys for maps" do
      query = from p in Post, select: %{p.id => p.title}
      assert_raise Ecto.SubQueryError, ~r/only atom keys are allowed/, fn ->
        plan(from(subquery(query), []))
      end
    end

    test "raises on custom expressions" do
      query = from p in Post, select: fragment("? + ?", p.id, p.id)
      assert_raise Ecto.SubQueryError, ~r/subquery\/cte must select a source \(t\), a field \(t\.field\) or a map/, fn ->
        plan(from(subquery(query), []))
      end
    end
  end

  describe "plan: where in subquery" do
    test "with params and then subquery" do
      p = from(p in Post, select: p.id, where: p.id in ^[2, 3])
      q = from(c in Comment, where: c.text == ^"1", where: c.post_id in subquery(p))

      {q, cast_params, dump_params, _} = plan(q)

      assert [_text, %{expr: expr, subqueries: [subquery]}] = q.wheres
      assert {:in, [], [{{:., [], [{:&, [], [0]}, :post_id]}, [], []}, {:subquery, 0}]} = expr
      assert %Ecto.SubQuery{} = subquery
      assert cast_params == ["1", 2, 3]
      assert dump_params == ["1", 2, 3]
    end

    test "with subquery and then param" do
      p = from(p in Post, select: p.id, where: p.id in ^[1, 2])
      q = from(c in Comment, where: c.post_id in subquery(p) and c.text == ^"3")

      {_, cast_params, dump_params, _} = plan(q)
      assert cast_params == [1, 2, "3"]
      assert dump_params == [1, 2, "3"]
    end

    test "with multiple subqueries" do
      p1 = from(p in Post, select: p.id, where: p.id == ^1)
      p2 = from(p in Post, select: p.id, where: p.id == ^2)
      c = from(c in Comment, where: c.post_id in subquery(p1) and c.post_id in subquery(p2))

      {_, cast_params, dump_params, _} = plan(c)
      assert cast_params == [1, 2]
      assert dump_params == [1, 2]
    end

    test "when subquery has nocache" do
      p = from(p in Post, select: p.id, where: p.id in ^[1])
      assert :nocache == p |> plan() |> elem(3)

      q = from(c in Comment, where: c.post_id in subquery(p))
      assert :nocache == q |> plan() |> elem(3)
    end

    test "when subquery has cache" do
      p1 = from(p in Post, select: p.id, where: p.id == ^1)
      k = p1 |> plan() |> elem(3)

      c1 = from(c in Comment, where: c.post_id in subquery(p1))
      cache = c1 |> plan() |> elem(3)
      assert [:all, {:where, [{:and, _expr, [sub]}]}, _source] = cache
      assert {:subquery, ^k} = sub

      # Invariance test.
      p2 = from(p in Post, select: p.id, where: p.id == ^2)
      assert ^k = p2 |> plan() |> elem(3)
      c2 = from(c in Comment, where: c.post_id in subquery(p2))
      assert ^cache = c2 |> plan() |> elem(3)
    end
  end

  describe "normalize: source subqueries" do
    test "keeps field types" do
      query = from p in subquery(Post), select: p.title

      assert normalize(query).select.fields ==
               [{{:., [type: :string], [{:&, [], [0]}, :title]}, [], []}]

      query = from p in subquery(from p in Post, select: p.title), select: p.title

      assert normalize(query).select.fields ==
               [{{:., [type: :string], [{:&, [], [0]}, :title]}, [], []}]

      query = from p in subquery(from p in Post, select: %{title: p.title}), select: p.title

      assert normalize(query).select.fields ==
               [{{:., [type: :string], [{:&, [], [0]}, :title]}, [], []}]
    end

    test "keeps field with nil values" do
      query = from p in subquery(from p in Post, select: %{title: nil})
      assert normalize(query).from.source.query.select.fields == [title: nil]
      assert normalize(query).select.fields == [{{:., [], [{:&, [], [0]}, :title]}, [], []}]
    end

    test "with params in from" do
      query = from p in Post,
                where: [title: ^"hello"],
                order_by: [asc: p.text == ^"world"]

      query = from p in subquery(query),
                where: p.text == ^"last",
                select: [p.title, ^"first"]

      {query, cast_params, dump_params} = normalize_with_params(query)
      assert [_, {:^, _, [0]}] = query.select.expr
      assert [%{expr: {:==, [], [_, {:^, [], [1]}]}}] = query.from.source.query.wheres
      assert [%{expr: [asc: {:==, [], [_, {:^, [], [2]}]}]}] = query.from.source.query.order_bys
      assert [%{expr: {:==, [], [_, {:^, [], [3]}]}}] = query.wheres
      assert cast_params == ["first", "hello", "world", "last"]
      assert dump_params == ["first", "hello", "world", "last"]
    end

    test "with params in join" do
      query = from p in Post,
                where: [title: ^"hello"],
                order_by: [asc: p.text == ^"world"]

      query = from c in Comment,
                join: p in subquery(query),
                on: p.text == ^"last",
                select: [p.title, ^"first"]

      {query, cast_params, dump_params} = normalize_with_params(query)
      assert [_, {:^, _, [0]}] = query.select.expr
      assert [%{expr: {:==, [], [_, {:^, [], [1]}]}}] = hd(query.joins).source.query.wheres
      assert [%{expr: [asc: {:==, [], [_, {:^, [], [2]}]}]}] = hd(query.joins).source.query.order_bys
      assert {:==, [], [_, {:^, [], [3]}]} = hd(query.joins).on.expr
      assert cast_params == ["first", "hello", "world", "last"]
      assert dump_params == ["first", "hello", "world", "last"]
    end

    test "merges fields when requested" do
      subquery = from p in Post, select: %{id: p.id, title: p.title}
      query = normalize(from(subquery(subquery), []))
      assert query.select.fields == select_fields([:id, :title], 0)

      query = normalize(from(p in subquery(subquery), select: p.title))
      assert query.select.fields == [{{:., [type: :string], [{:&, [], [0]}, :title]}, [], []}]

      query = normalize(from(c in Comment, join: p in subquery(subquery), select: p))
      assert query.select.fields == select_fields([:id, :title], 1)

      query = normalize(from(c in Comment, join: p in subquery(subquery), select: p.title))
      assert query.select.fields == [{{:., [type: :string], [{:&, [], [1]}, :title]}, [], []}]

      subquery = from p in Post, select: %{id: p.id, title: p.title}
      query = normalize(from(p in subquery(subquery), select: [:title]))
      assert query.select.fields == [{{:., [], [{:&, [], [0]}, :title]}, [], []}]

      subquery = from p in Post, select: %{id: p.id, title: p.title}
      query = normalize(from(p in subquery(subquery), select: map(p, [:title])))
      assert query.select.fields == [{{:., [], [{:&, [], [0]}, :title]}, [], []}]

      assert_raise Ecto.QueryError, ~r/it is not possible to return a struct subset of a subquery/, fn ->
        subquery = from p in Post, select: %{id: p.id, title: p.title}
        normalize(from(p in subquery(subquery), select: struct(p, [:title])))
      end
    end

    test "invalid usage" do
      assert_raise Ecto.SubQueryError, ~r/does not allow `update` expressions in query/, fn ->
        query = from p in Post, update: [set: [title: nil]]
        normalize(from(subquery(query), []))
      end

      assert_raise Ecto.QueryError, ~r/`update_all` does not allow subqueries in `from`/, fn ->
        query = from p in Post
        normalize(from(subquery(query), update: [set: [title: nil]]), :update_all)
      end
    end
  end

  describe "normalize: where in subquery" do
    test "in query" do
      c = from(c in Comment, where: c.text == ^"foo", select: c.post_id)
      s = from(p in Post, where: p.id in subquery(c), select: count())
      assert {:in, _, [_, {:subquery, 0}]} = hd(s.wheres).expr
      assert [{:subquery, 0}] = hd(s.wheres).params

      {n, cast_params, dump_params} = normalize_with_params(s)
      assert {:in, _, [_, %Ecto.SubQuery{} = subquery]} = hd(n.wheres).expr
      assert [{{:., _, [_, :post_id]}, _, []}] = subquery.query.select.fields
      assert cast_params == ["foo"]
      assert dump_params == ["foo"]
    end

    test "in dynamic" do
      c = from(c in Comment, where: c.text == ^"foo", select: c.post_id)
      d = dynamic([p], p.id in subquery(c))
      s = from(p in Post, where: ^d, select: count())
      assert {:in, _, [_, {:subquery, 0}]} = hd(s.wheres).expr
      assert [{:subquery, 0}] = hd(s.wheres).params

      {n, cast_params, dump_params} = normalize_with_params(s)
      assert {:in, _, [_, %Ecto.SubQuery{} = subquery]} = hd(n.wheres).expr
      assert [{{:., _, [_, :post_id]}, _, []}] = subquery.query.select.fields
      assert cast_params == ["foo"]
      assert dump_params == ["foo"]
    end

    test "in multiple dynamic" do
      cbar = from(c in Comment, where: c.text == ^"bar", select: c.post_id)
      cfoo = from(c in Comment, where: c.text == ^"foo", select: c.post_id)
      d1 = dynamic([p], p.id not in subquery(cbar))
      d2 = dynamic([p], p.id in subquery(cfoo) and ^d1)
      s = from(p in Post, where: ^d2, select: count())

      assert {:and, _, [
                {:in, _, [_, {:subquery, 0}]},
                {:not, _, [{:in, _, [_, {:subquery, 1}]}]},
              ]} = hd(s.wheres).expr

      assert [{:subquery, 0}, {:subquery, 1}] = hd(s.wheres).params

      {n, cast_params, dump_params} = normalize_with_params(s)

      assert {:and, _, [
                {:in, _, [_, %Ecto.SubQuery{} = subqueryfoo]},
                {:not, _, [{:in, _, [_, %Ecto.SubQuery{} = subquerybar]}]},
              ]} = hd(n.wheres).expr

      assert Macro.to_string(hd(subqueryfoo.query.wheres).expr) == "&0.text() == ^0"
      assert Macro.to_string(hd(subquerybar.query.wheres).expr) == "&0.text() == ^1"
      assert subqueryfoo.params == [{"foo", "foo"}]
      assert subquerybar.params == [{"bar", "bar"}]
      assert cast_params == ["foo", "bar"]
      assert dump_params == ["foo", "bar"]
    end

    test "with aggregate" do
      c = from(c in Comment, where: c.text == ^"foo", select: max(c.post_id))
      s = from(p in Post, where: p.id in subquery(c), select: count())

      assert {:in, _, [_, {:subquery, 0}]} = hd(s.wheres).expr
      assert {:in, _, [_, %Ecto.SubQuery{} = subquery]} = hd(normalize(s).wheres).expr
      assert [{:max, _, _}] = subquery.query.select.fields
    end

    test "with too many selected expressions" do
      assert_raise Ecto.QueryError, ~r/^subquery must return a single field in order to be used on the right-side of `in`/, fn ->
        p = from(p in Post, select: {p.id, p.title})
        from(c in Comment, where: c.post_id in subquery(p)) |> normalize()
      end
    end
  end
end
