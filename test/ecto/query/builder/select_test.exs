defmodule Ecto.Query.Builder.SelectTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Builder.Select
  doctest Ecto.Query.Builder.Select

  defmodule Post do
    defstruct [:title]
  end

  defmodule Comment do
    use Ecto.Schema

    @primary_key false
    schema "comments" do
      field :title, :string
      field :likes, :integer
      field :dislikes, :integer, load_in_query: false
    end
  end

  defp params_acc(opts \\ []) do
    params = opts[:params] || []
    take = opts[:take] || %{}
    subqueries = opts[:subqueries] || []
    aliases = opts[:aliases] || %{}
    {params, %{take: take, subqueries: subqueries, aliases: aliases}}
  end

  describe "escape" do
    test "handles expressions and params" do
      assert {Macro.escape(quote do &0 end), params_acc()} ==
             escape(quote do x end, [x: 0], __ENV__)

      assert {Macro.escape(quote do &0.y() end), params_acc()} ==
             escape(quote do x.y() end, [x: 0], __ENV__)

      assert {Macro.escape(quote do &0 end), params_acc(take: %{0 => {:any, [:foo, :bar, baz: :bat]}})} ==
             escape(quote do [:foo, :bar, baz: :bat] end, [x: 0], __ENV__)

      assert {Macro.escape(quote do &0 end), params_acc(take: %{0 => {:struct, [:foo, :bar, baz: :bat]}})} ==
             escape(quote do struct(x, [:foo, :bar, baz: :bat]) end, [x: 0], __ENV__)

      assert {Macro.escape(quote do &0 end), params_acc(take: %{0 => {:map, [:foo, :bar, baz: :bat]}})} ==
             escape(quote do map(x, [:foo, :bar, baz: :bat]) end, [x: 0], __ENV__)

      assert {{:{}, [], [:{}, [], [0, 1, 2]]}, params_acc()} ==
             escape(quote do {0, 1, 2} end, [], __ENV__)

      assert {{:{}, [], [:%{}, [], [a: {:{}, [], [:&, [], [0]]}]]}, params_acc()} ==
             escape(quote do %{a: a} end, [a: 0], __ENV__)

      assert {{:{}, [], [:%{}, [], [{{:{}, [], [:&, [], [0]]}, {:{}, [], [:&, [], [1]]}}]]}, params_acc()} ==
             escape(quote do %{a => b} end, [a: 0, b: 1], __ENV__)

      assert {[Macro.escape(quote do &0.y() end), Macro.escape(quote do &0.z() end)], params_acc()} ==
             escape(quote do [x.y(), x.z()] end, [x: 0], __ENV__)

      assert {[{:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :y]]}, [], []]},
               {:{}, [], [:^, [], [0]]}], params_acc(params: [{1, :any}])} ==
              escape(quote do [x.y(), ^1] end, [x: 0], __ENV__)

      assert {{:{}, [], [:%, [], [Foo, {:{}, [], [:%{}, [], [a: {:{}, [], [:&, [], [0]]}]]}]]}, params_acc()} ==
             escape(quote do %Foo{a: a} end, [a: 0], __ENV__)
    end

    test "on conflicting take" do
      assert {_, {[], %{take: %{0 => {:map, [:foo, :bar, baz: :bat]}}, subqueries: []}}} =
             escape(quote do {map(x, [:foo, :bar]), map(x, [baz: :bat])} end, [x: 0], __ENV__)

      assert_raise Ecto.Query.CompileError,
                   ~r"cannot select_merge because the binding at position 0",
                   fn ->
        escape(quote do {map(x, [:foo, :bar]), struct(x, [baz: :bat])} end, [x: 0], __ENV__)
      end
    end

    @fields [:field]

    test "supports sigils/attributes" do
      fields = ~w[field]a
      assert select("q", [q], map(q, ~w[field]a)).select.take == %{0 => {:map, fields}}
      assert select("q", [q], struct(q, @fields)).select.take == %{0 => {:struct, fields}}
      assert select("q", [q], ~w[field]a).select.take == %{0 => {:any, fields}}
    end

    test "raises on single atom" do
      assert_raise Ecto.Query.CompileError,
                   ~r":foo is not a valid query expression, :select expects a query expression or a list of fields",
                   fn ->
        escape(quote do :foo end, [x: 0], __ENV__)
      end
    end

    test "raises on mixed fields and interpolation" do
      assert_raise Ecto.Query.CompileError, ~r"Cannot mix fields with interpolations", fn ->
        escape(quote do [:foo, ^:bar] end, [], __ENV__)
      end
    end

    test "supports aliasing a selected value with selected_as/2" do
      escaped_alias = {:selected_as, [], [{{:., [], [{:&, [], [0]}, :id]}, [], []}, :ident]}

      # single field
      query = from p in "posts", select: selected_as(p.id, :ident)
      assert escaped_alias == query.select.expr

      query = select("posts", [p], selected_as(p.id, :ident))
      assert escaped_alias == query.select.expr

      # maps
      query = from p in "posts", select: %{id: selected_as(p.id, :ident)}
      assert {:%{}, [], [id: escaped_alias]} == query.select.expr

      query = select("posts", [p], %{id: selected_as(p.id, :ident)})
      assert {:%{}, [], [id: escaped_alias]} == query.select.expr

      # structs
      query = from p in "posts", select: %{p | id: selected_as(p.id, :ident)}
      assert {:%{}, [], [{:|, [], [{:&, [], [0]}, [id: escaped_alias]]}]} == query.select.expr

      query = select("posts", [p], %{p | id: selected_as(p.id, :ident)})
      assert {:%{}, [], [{:|, [], [{:&, [], [0]}, [id: escaped_alias]]}]} == query.select.expr

      # keyword lists
      query = from p in "posts", select: [id: selected_as(p.id, :ident)]
      assert [{:{}, [], [:id, escaped_alias]}] == query.select.expr

      query = select("posts", [p], [id: selected_as(p.id, :ident)])
      assert [{:{}, [], [:id, escaped_alias]}] == query.select.expr
    end

    test "supports aliasing a selected value in select_merge with selected_as/2" do
      escaped_select_alias = {:selected_as, [], [{{:., [], [{:&, [], [0]}, :visits]}, [], []}, :select]}
      escaped_merge_alias = {:selected_as, [], [{{:., [], [{:&, [], [0]}, :title]}, [], []}, :merge]}

      # merging into a map
      query = from p in "posts", select: %{v: selected_as(p.visits, :select)}, select_merge: %{title: selected_as(p.title, :merge)}
      assert {:%{}, [], [v: escaped_select_alias, title: escaped_merge_alias]} == query.select.expr
      assert %{select: _, merge: _} = query.select.aliases

      # merging into a source
      query = from c in Comment, select_merge: %{title: selected_as(c.title, :merge)}
      assert {:merge, [], [{:&, [], [0]}, {:%{}, [], [title: escaped_merge_alias]}]} == query.select.expr
      assert %{merge: _} = query.select.aliases
    end

    test "supports dynamic selected values with selected_as/2" do
      escaped_alias = {:selected_as, [], [{{:., [], [{:&, [], [0]}, :title]}, [], []}, :alias]}
      escaped_alias2 = {:selected_as, [], [{{:., [], [{:&, [], [0]}, :title]}, [], []}, :alias2]}

      # map
      select_fields = %{title: dynamic([p], p.title |> selected_as(:alias))}
      merge_fields = %{title2: dynamic([p], selected_as(p.title, :alias2))}

      query = from p in "posts", select: ^select_fields, select_merge: ^merge_fields
      assert {:%{}, [], [title: escaped_alias, title2: escaped_alias2]} == query.select.expr
      assert %{alias: _, alias2: _} = query.select.aliases

      # struct
      fields = %Post{
        title: dynamic([p], selected_as(p.title, :alias)),
      }

      query = from p in "posts", select: ^fields
      assert {:%, [], [_, {:%{}, [], [title: escaped_alias]}]} = query.select.expr
      assert %{alias: _} = query.select.aliases

      # single field
      field = dynamic([p], selected_as(p.title, :alias))
      query = from p in "posts", select: ^field
      assert escaped_alias == query.select.expr
      assert %{alias: _} = query.select.aliases
    end

    defmacro my_custom_field(p) do
      quote do
        fragment("lower(?)", unquote(p).title)
      end
    end

    defmacro my_complex_order(p) do
      quote do
        [desc: unquote(p).id, asc: my_custom_field(unquote(p)), asc: nth_value(unquote(p).links, 1)]
      end
    end

    test "supports macro expansion in over/2" do
      query = from p in "posts", select: %{row_number: over(row_number(), order_by: [desc: my_custom_field(p)])}

      assert {:%{}, [],
       [
         row_number:
           {:over, [],
            [
              {:row_number, [], []},
              [
                order_by: [
                  desc: {:fragment, [], [raw: "lower(", expr: _, raw: ")"]}
                ]
              ]
            ]}
       ]} = query.select.expr

      query = from p in "posts", select: %{row_number: over(row_number(), order_by: my_complex_order(p))}
      assert {:%{}, [],
        [
          row_number:
            {:over, [],
              [
                {:row_number, [], []},
                [
                  order_by: [
                    desc: _,
                    asc: {:fragment, [], [raw: "lower(", expr: _, raw: ")"]},
                    asc: {:nth_value, [], _}
                  ]
                ]
              ]}
        ]} = query.select.expr
    end

    test "raises if name given to selected_as/2 is not an atom" do
      message = "expected literal atom or interpolated value in selected_as/2, got: `\"ident\"`"

      assert_raise Ecto.Query.CompileError, message, fn ->
        escape(quote do selected_as(p.id, "ident") end, [], __ENV__)
      end
    end

    test "raises if the name given to selected_as/2 already exists" do
      message = "the alias `:visits` has been specified more than once using `selected_as/2`"

      assert_raise Ecto.Query.CompileError, message, fn ->
        select_expr = quote do %{visits: selected_as(p.visits, :visits), visits2: selected_as(p.visits, :visits)} end
        escape(select_expr, [p: 0], __ENV__)
      end

      assert_raise Ecto.Query.CompileError, message, fn ->
        from p in "posts", select: selected_as(p.visits, :visits), select_merge: %{visits: selected_as(p.visits, :visits)}
      end
    end

    test "raises if selected_as/2 is not at the root of the select statement" do
      message = ~r/selected_as\/2 can only be used at the root of a select statement/

      assert_raise Ecto.Query.CompileError, message, fn ->
        select_expr = quote do coalesce(selected_as(p.visits, :v), 0) end
        escape(select_expr, [p: 0], __ENV__)
      end
    end
  end

  describe "at runtime" do
    test "supports interpolation" do
      fields = [:foo, :bar, :baz]
      assert select("q", ^fields).select.take == %{0 => {:any, fields}}
      assert select("q", [:foo, :bar, :baz]).select == select("q", ^fields).select
      assert select("q", [q], map(q, ^fields)).select.take == %{0 => {:map, fields}}
      assert select("q", [q], struct(q, ^fields)).select.take == %{0 => {:struct, fields}}
    end

    test "supports single dynamic value interpolated at root level" do
      as = :blog
      field = :title

      ref = dynamic(field(as(^as), ^field))
      query = from(b in "blogs", select: ^ref)

      assert Macro.to_string(query.select.expr) == "as(:blog).title()"
    end

    test "supports map with dynamic values interpolated at root level" do
      as = :blog
      field = :title

      ref = dynamic(field(as(^as), ^field))
      query = from(b in "blogs", select: ^%{title: ref, other: 8})

      assert Macro.to_string(query.select.expr) == "%{other: 8, title: as(:blog).title()}"
    end

    test "supports arbitrary struct with dynamic values interpolated at root level" do
      as = :blog
      field = :title

      ref = dynamic(field(as(^as), ^field))
      query = from(b in "blogs", select: ^%Post{title: ref})

      assert Macro.to_string(query.select.expr) == "%Ecto.Query.Builder.SelectTest.Post{title: as(:blog).title()}"
    end

    test "supports nested map with dynamic values interpolated at root level" do
      as = :blog
      field = :title

      ref = dynamic(field(as(^as), ^field))
      query = from(b in "blogs", select: ^%{fields: %{title: ref}})

      assert Macro.to_string(query.select.expr) == "%{fields: %{title: as(:blog).title()}}"
    end

    test "supports dynamic select_merge" do
      as = :blog
      field = :title

      ref = dynamic(field(as(^as), ^field))
      query = from(b in "blogs", select: %{t: b.title}, select_merge: ^%{title: ref})

      assert Macro.to_string(query.select.expr) == "%{t: &0.title(), title: as(:blog).title()}"
    end

    test "supports subqueries" do
      subquery = from(u in "users", where: parent_as(^:list).created_by_id == u.id, select: u.email)

      query =
        from(l in "lists",
          as: :list,
          select: %{title: l.archived_at, user_email: subquery(subquery)}
        )

      assert Macro.to_string(query.select.expr) ==
              "%{title: &0.archived_at(), user_email: {:subquery, 0}}"

      assert length(query.select.subqueries) == 1
      assert length(query.select.params) == 1
    end

    test "supports subqueries in interpolated map at root level" do
      subquery = from(u in "users", where: parent_as(^:list).created_by_id == u.id, select: u.email)

      query =
        from(l in "lists",
          as: :list,
          select: ^%{user_email: subquery(subquery)}
        )

      assert Macro.to_string(query.select.expr) ==
              "%{user_email: {:subquery, 0}}"

      assert length(query.select.subqueries) == 1
      assert length(query.select.params) == 1
    end

    test "supports multiple nested partly dynamic subqueries" do
      created_by_id = 8
      ignore_template_id = 9

      subquery0 =
        from(t in "tasks",
          where: t.list_id == parent_as(:list).id and t.created_by_id == ^created_by_id,
          select: max(t.due_on)
        )

      subquery1 =
        from(t in "templates", where: parent_as(^:list).from_template_id == t.id, select: t.title)

      subquery2 =
        from(u in "users", where: parent_as(^:list).created_by_id == u.id, select: u.email)

      ref =
        dynamic(
          [l],
          fragment(
            "CASE WHEN ? THEN ? ELSE ? END",
            l.from_template_id == ^ignore_template_id,
            "",
            subquery(subquery1)
          )
        )

      query =
        from(l in "lists",
          as: :list,
          select: %{
            title: l.archived_at,
            maxdue: subquery(subquery0),
            user_email: subquery(subquery2)
          },
          select_merge: ^%{template_name: ref}
        )

      assert Macro.to_string(query.select.expr) == """
            %{\n\
              title: &0.archived_at(),\n\
              maxdue: {:subquery, 0},\n\
              user_email: {:subquery, 1},\n\
              template_name:\n\
                fragment(\n\
                  {:raw, "CASE WHEN "},\n\
                  {:expr, &0.from_template_id() == ^2},\n\
                  {:raw, " THEN "},\n\
                  {:expr, ""},\n\
                  {:raw, " ELSE "},\n\
                  {:expr, {:subquery, 2}},\n\
                  {:raw, " END"}\n\
                )\n\
            }\
            """

      assert length(query.select.subqueries) == 3
      assert query.select.params == [{:subquery, 0}, {:subquery, 1}, {ignore_template_id, {0, :from_template_id}}, {:subquery, 2}]
    end

    test "supports interpolated atom names in selected_as/2" do
      escaped_alias1 = {:selected_as, [], [{{:., [], [{:&, [], [0]}, :id]}, [], []}, :ident]}
      escaped_alias2 = {:selected_as, [], [{{:., [], [{:&, [], [0]}, :id]}, [], []}, :ident2]}

      query1 = from p in "posts", select: {selected_as(p.id, ^:ident), selected_as(p.id, :ident2)}
      query2 = from p in "posts", select: {selected_as(p.id, :ident), selected_as(p.id, ^:ident2)}
      query3 = from p in "posts", select: {selected_as(p.id, ^:ident), selected_as(p.id, ^:ident2)}

      assert query1.select.expr == query2.select.expr
      assert query2.select.expr == query3.select.expr
      assert query1.select.aliases == query2.select.aliases
      assert query2.select.aliases == query3.select.aliases
      assert %{ident: _, ident2: _} = query1.select.aliases
      assert {:{}, [], [escaped_alias1, escaped_alias2]} == query1.select.expr

      message = "expected atom in selected_as/2, got: `\"ident\"`"

      assert_raise Ecto.Query.CompileError, message, fn ->
        from p in "posts", select: selected_as(p.id, ^"ident")
      end
    end

    test "supports interpolated atom names in selected_as/2 with dynamic/2" do
      escaped_alias = {:selected_as, [], [{{:., [], [{:&, [], [0]}, :title]}, [], []}, :alias]}
      escaped_alias2 = {:selected_as, [], [{{:., [], [{:&, [], [0]}, :title]}, [], []}, :alias2]}

      select_fields = %{title: dynamic([p], selected_as(p.title, ^:alias))}
      merge_fields = %{title2: dynamic([p], selected_as(p.title, ^:alias2))}

      query = from p in "posts", select: ^select_fields, select_merge: ^merge_fields
      assert {:%{}, [], [title: escaped_alias, title2: escaped_alias2]} == query.select.expr
      assert %{alias: _, alias2: _} = query.select.aliases
    end

    test "supports interpolated atom names in selected_as/2 with select_merge" do
      escaped_select_alias = {:selected_as, [], [{{:., [], [{:&, [], [0]}, :visits]}, [], []}, :select]}
      escaped_merge_alias = {:selected_as, [], [{{:., [], [{:&, [], [0]}, :title]}, [], []}, :merge]}

      # merging into a map
      select = :select
      merge = :merge
      query = from p in "posts", select: %{v: selected_as(p.visits, ^select)}, select_merge: %{title: selected_as(p.title, ^merge)}
      assert query.select.expr == {:%{}, [], [v: escaped_select_alias, title: escaped_merge_alias]}
      assert %{select: _, merge: _} = query.select.aliases

      # merging into a source
      query = from c in Comment, select_merge: %{title: selected_as(c.title, ^:merge)}
      assert query.select.expr == {:merge, [], [{:&, [], [0]}, {:%{}, [], [title: escaped_merge_alias]}]}
      assert %{merge: _} = query.select.aliases
    end

    test "raises on list or tuple values in interpolated map" do
      message = ~r/Interpolated map values in :select can only be/

      assert_raise Ecto.QueryError, message, fn ->
        %Ecto.Query{} |> select(^%{foo: [:bar]})
      end

      assert_raise Ecto.QueryError, message, fn ->
        %Ecto.Query{} |> select(^%{foo: {:ok, :bar}})
      end
    end

    test "raises on multiple selects" do
      message = "only one select expression is allowed in query"
      assert_raise Ecto.Query.CompileError, message, fn ->
        %Ecto.Query{} |> select([], 1) |> select([], 2)
      end
    end

    test "supports interpolated map keys" do
      key = :test_key

      q = from p in "posts", select: %{^key => 1}
      assert {:%{}, [], [test_key: 1]} = q.select.expr

      q = from p in "posts", select: %{^:test_key => 1}
      assert {:%{}, [], [test_key: 1]} = q.select.expr
    end

    test "supports literal maps inside dynamic" do
      map = dynamic([p], %{id: p.id, title: p.title})
      q = from p in "posts", select: ^map

      assert Macro.to_string(q.select.expr) == "%{id: &0.id(), title: &0.title()}"
    end
  end

  describe "select_merge" do
    test "merges at compile time" do
      query =
        from p in "posts",
          select: %{},
          select_merge: %{a: map(p, [:title]), b: ^0},
          select_merge: %{c: map(p, [:title, :body]), d: ^1}

      assert Macro.to_string(query.select.expr) == "%{a: &0, b: ^0, c: &0, d: ^1}"
      assert query.select.params == [{0, :any}, {1, :any}]
      assert query.select.take == %{0 => {:map, [:title, :body]}}
    end

    test "merges at runtime" do
      query =
        "posts"
        |> select([], %{})
        |> select_merge([p], %{a: map(p, [:title]), b: ^0})
        |> select_merge([p], %{c: map(p, [:title, :body]), d: ^1})

      assert Macro.to_string(query.select.expr) == "%{a: &0, b: ^0, c: &0, d: ^1}"
      assert query.select.params == [{0, :any}, {1, :any}]
      assert query.select.take == %{0 => {:map, [:title, :body]}}
    end

    test "merges at the root" do
      query =
        "posts"
        |> select([], %{})
        |> select_merge([p], map(p, [:title]))
        |> select_merge([p], %{body: ^"body"})

      assert Macro.to_string(query.select.expr) == "merge(&0, %{body: ^0})"
      assert query.select.params == [{"body", :any}]
      assert query.select.take == %{0 => {:map, [:title]}}
    end

    test "merges at the root with interpolated fields" do
      fields = [:title]

      query =
        "posts"
        |> select([], %{})
        |> select_merge([p], map(p, ^fields))
        |> select_merge([p], %{body: ^"body"})

      assert Macro.to_string(query.select.expr) == "merge(&0, %{body: ^0})"
      assert query.select.params == [{"body", :any}]
      assert query.select.take == %{0 => {:map, [:title]}}
    end

    test "merges at the root with interpolated fields with explicit merge" do
      fields = [:title]

      query = select("posts", [p], merge(map(p, ^fields), %{body: ^"body"}))
      assert Macro.to_string(query.select.expr) == "merge(&0, %{body: ^0})"
      assert query.select.params == [{"body", :any}]
      assert query.select.take == %{0 => {:map, [:title]}}

      query = select("posts", [p], merge(%{body: ^"body"}, map(p, ^fields)))
      assert Macro.to_string(query.select.expr) == "merge(%{body: ^0}, &0)"
      assert query.select.params == [{"body", :any}]
      assert query.select.take == %{0 => {:map, [:title]}}
    end

    test "merges dynamically" do
      query =
        from(b in "blogs",
          as: :blog,
          join: p in "posts",
          as: :post,
          on: p.blog_id == b.id,
          join: c in "comments",
          as: :comment,
          on: c.post_id == p.id,
          select: %{comments: count(c.id)}
        )

      query =
        Enum.reduce([blog: :name, post: :author], query, fn {binding, field}, query ->
          query
          |> select_merge([{^binding, bound}], %{^field => field(bound, ^field)})
          |> group_by([{^binding, bound}], field(bound, ^field))
        end)

      assert Macro.to_string(query.select.expr) ==
               "%{comments: count(&2.id()), name: &0.name(), author: &1.author()}"
    end

    test "supports '...' in binding list with no prior select" do
      query =
        "posts"
        |> select_merge([..., p], %{title: p.title})

      assert Macro.to_string(query.select.expr) == "merge(&0, %{title: &0.title()})"
      assert query.select.params == []
      assert query.select.take == %{}
    end

    test "raises on incompatible pairs" do
      assert_raise Ecto.QueryError, ~r/those select expressions are incompatible/, fn ->
        from p in "posts",
          select: %{title: p.title},
          select_merge: %Post{title: nil}
      end
    end

    test "defaults to struct" do
      query = select_merge("posts", [p], %{title: nil})
      assert Macro.to_string(query.select.expr) == "merge(&0, %{title: nil})"
      assert query.select.params == []
      assert query.select.take == %{}
    end

    test "with take" do
      # On select with schemaless source
      query = from c in "comments", select: c, select_merge: [:title]

      assert Macro.to_string(query.select.expr) == "&0"
      assert query.select.params == []
      assert query.select.take == %{}

      # On select with schema
      query = from c in Comment, select: c, select_merge: [:dislikes]

      assert Macro.to_string(query.select.expr) == "&0"
      assert query.select.params == []
      assert query.select.take == %{0 => {:any, [:dislikes, :title, :likes]}}

      query = from p in "posts", join: c in Comment, on: true, select: c, select_merge: map(c, [:dislikes])

      assert Macro.to_string(query.select.expr) == "&1"
      assert query.select.params == []
      assert query.select.take == %{1 => {:map, [:dislikes, :title, :likes]}}

      # On take with schemaless source
      query = from c in "comments", select: [:title], select_merge: [:likes]

      assert Macro.to_string(query.select.expr) == "&0"
      assert query.select.params == []
      assert query.select.take == %{0 => {:any, [:title, :likes]}}

      # On take with schema
      query = from c in Comment, select: [:title], select_merge: [:dislikes]

      assert Macro.to_string(query.select.expr) == "&0"
      assert query.select.params == []
      assert query.select.take == %{0 => {:any, [:title, :dislikes]}}
    end

    test "on conflicting take" do
      _ = from p in "posts", select: p, select_merge: map(p, [:title]), select_merge: [:body]
      _ = from p in "posts", select: p, select_merge: map(p, [:title]), select_merge: map(p, [:body])
      _ = from p in "posts", select: p, select_merge: [:title], select_merge: map(p, [:body])
      _ = from p in "posts", select: p, select_merge: [:title], select_merge: struct(p, [:body])
      _ = from p in "posts", select: p, select_merge: struct(p, [:title]), select_merge: [:body]
      _ = from p in "posts", select: p, select_merge: struct(p, [:title]), select_merge: struct(p, [:body])

      assert_raise Ecto.Query.CompileError,
                   ~r"cannot select_merge because the binding at position 0",
                   fn ->
        from p in "posts", select: map(p, [:title]), select_merge: struct(p, [:title])
      end
    end

    test "optimizes map/struct merges" do
      query =
        from p in "posts",
          select: %{t: {p.title, p.body}},
          select_merge: %{t: p.title, b: p.body}
      assert Macro.to_string(query.select.expr) == "%{t: &0.title(), b: &0.body()}"

      query =
        from p in "posts",
          select: %Post{title: p.title},
          select_merge: %{title: nil}
      assert Macro.to_string(query.select.expr) == "%Ecto.Query.Builder.SelectTest.Post{title: nil}"

      query =
        from p in "posts",
          select: %{t: {p.title, ^0}},
          select_merge: %{t: p.title, b: p.body}
      assert Macro.to_string(query.select.expr) =~ "merge"
    end

    test "supports interpolated map keys" do
      shared_key = :shared
      merge_key = :merge

      q =
        from p in "posts",
          select: %{^shared_key => :old},
          select_merge: %{^shared_key => :new, ^merge_key => :merge}

      assert {:%{}, [], [shared: :new, merge: :merge]} = q.select.expr

      q =
        from p in "posts",
          select: %{^:shared => :old},
          select_merge: %{^:shared => :new, ^:merge => :merge}

      assert {:%{}, [], [shared: :new, merge: :merge]} = q.select.expr
    end

    test "merge map literals with no conflicting keys" do
      # without inner interpolations/subqueries
      query = from p in "posts", select: %{id: 1, title: "hi"}, select_merge: %{visits: ^2}
      assert Macro.to_string(query.select.expr) == "%{id: 1, title: \"hi\", visits: ^0}"

      # with inner interpolation
      query = from p in "posts", select: %{id: ^1, title: "hi"}, select_merge: %{visits: ^2}
      assert Macro.to_string(query.select.expr) == "%{id: ^0, title: \"hi\", visits: ^1}"

      # with inner subquery
      s = from p in "posts", select: p.title, limit: 1
      query = from p in "posts", select: %{id: 1, title: subquery(s)}, select_merge: %{visits: ^2}
      assert Macro.to_string(query.select.expr) == "%{id: 1, title: {:subquery, 0}, visits: ^1}"
    end

    test "merge map literals with conflicting keys" do
      # without inner params
      query = from p in "posts", select: %{id: 1, title: "hi"}, select_merge: %{id: ^2}
      assert Macro.to_string(query.select.expr) == "%{title: \"hi\", id: ^0}"

      # with inner params
      query = from p in "posts", select: %{id: ^1, title: "hi"}, select_merge: %{id: ^2}
      assert Macro.to_string(query.select.expr) == "merge(%{id: ^0, title: \"hi\"}, %{id: ^1})"

      # with inner subqueries
      s = from p in "posts", select: p.title, limit: 1
      query = from p in "posts", select: %{id: 1, title: subquery(s)}, select_merge: %{id: ^2}
      assert Macro.to_string(query.select.expr) == "merge(%{id: 1, title: {:subquery, 0}}, %{id: ^1})"
    end
  end
end
