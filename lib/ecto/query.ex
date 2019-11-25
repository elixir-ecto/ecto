defmodule Ecto.SubQuery do
  @moduledoc """
  A struct representing subqueries.

  See `Ecto.Query.subquery/2` for more information.
  """
  defstruct [:query, :params, :select, :cache]
end

defmodule Ecto.Query do
  @moduledoc ~S"""
  Provides the Query DSL.

  Queries are used to retrieve and manipulate data from a repository
  (see `Ecto.Repo`). Ecto queries come in two flavors: keyword-based
  and macro-based. Most examples will use the keyword-based syntax,
  the macro one will be explored in later sections.

  Let's see a sample query:

      # Imports only from/2 of Ecto.Query
      import Ecto.Query, only: [from: 2]

      # Create a query
      query = from u in "users",
                where: u.age > 18,
                select: u.name

      # Send the query to the repository
      Repo.all(query)

  In the example above, we are directly querying the "users" table
  from the database.

  ## Query expressions

  Ecto allows a limited set of expressions inside queries. In the
  query below, for example, we use `u.age` to access a field, the
  `>` comparison operator and the literal `0`:

      query = from u in "users", where: u.age > 0, select: u.name

  You can find the full list of operations in `Ecto.Query.API`.
  Besides the operations listed there, the following literals are
  supported in queries:

    * Integers: `1`, `2`, `3`
    * Floats: `1.0`, `2.0`, `3.0`
    * Booleans: `true`, `false`
    * Binaries: `<<1, 2, 3>>`
    * Strings: `"foo bar"`, `~s(this is a string)`
    * Arrays: `[1, 2, 3]`, `~w(interpolate words)`

  All other types and dynamic values must be passed as a parameter using
  interpolation as explained below.

  ## Interpolation and casting

  External values and Elixir expressions can be injected into a query
  expression with `^`:

      def with_minimum(age, height_ft) do
        from u in "users",
          where: u.age > ^age and u.height > ^(height_ft * 3.28),
          select: u.name
      end

      with_minimum(18, 5.0)

  When interpolating values, you may want to explicitly tell Ecto
  what is the expected type of the value being interpolated:

      age = "18"
      Repo.all(from u in "users",
                where: u.age > type(^age, :integer),
                select: u.name)

  In the example above, Ecto will cast the age to type integer. When
  a value cannot be cast, `Ecto.Query.CastError` is raised.

  To avoid the repetition of always specifying the types, you may define
  an `Ecto.Schema`. In such cases, Ecto will analyze your queries and
  automatically cast the interpolated "age" when compared to the `u.age`
  field, as long as the age field is defined with type `:integer` in
  your schema:

      age = "18"
      Repo.all(from u in User, where: u.age > ^age, select: u.name)

  Another advantage of using schemas is that we no longer need to specify
  the select option in queries, as by default Ecto will retrieve all
  fields specified in the schema:

      age = "18"
      Repo.all(from u in User, where: u.age > ^age)

  For this reason, we will use schemas on the remaining examples but
  remember Ecto does not require them in order to write queries.

  ## `nil` comparison

  `nil` comparison in filters, such as where and having, is forbidden
  and it will raise an error:

      # Raises if age is nil
      from u in User, where: u.age == ^age

  This is done as a security measure to avoid attacks that attempt
  to traverse entries with nil columns. To check that value is `nil`,
  use `is_nil/1` instead:

      from u in User, where: is_nil(u.age)

  ## Composition

  Ecto queries are composable. For example, the query above can
  actually be defined in two parts:

      # Create a query
      query = from u in User, where: u.age > 18

      # Extend the query
      query = from u in query, select: u.name

  Composing queries uses the same syntax as creating a query.
  The difference is that, instead of passing a schema like `User`
  on the right side of `in`, we passed the query itself.

  Any value can be used on the right-side of `in` as long as it implements
  the `Ecto.Queryable` protocol. For now, we know the protocol is
  implemented for both atoms (like `User`) and strings (like "users").

  In any case, regardless if a schema has been given or not, Ecto
  queries are always composable thanks to its binding system.

  ### Positional bindings

  On the left side of `in` we specify the query bindings.  This is
  done inside from and join clauses.  In the query below `u` is a
  binding and `u.age` is a field access using this binding.

      query = from u in User, where: u.age > 18

  Bindings are not exposed from the query.  When composing queries, you
  must specify bindings again for each refinement query.  For example,
  to further narrow down the above query, we again need to tell Ecto what
  bindings to expect:

      query = from u in query, select: u.city

  Bindings in Ecto are positional, and the names do not have to be
  consistent between input and refinement queries. For example, the
  query above could also be written as:

      query = from q in query, select: q.city

  It would make no difference to Ecto. This is important because
  it allows developers to compose queries without caring about
  the bindings used in the initial query.

  When using joins, the bindings should be matched in the order they
  are specified:

      # Create a query
      query = from p in Post,
                join: c in Comment, on: c.post_id == p.id

      # Extend the query
      query = from [p, c] in query,
                select: {p.title, c.body}

  You are not required to specify all bindings when composing.
  For example, if we would like to order the results above by
  post insertion date, we could further extend it as:

      query = from q in query, order_by: q.inserted_at

  The example above will work if the input query has 1 or 10
  bindings. As long as the number of bindings is less than the
  number of from + joins, Ecto will match only what you have
  specified. The first binding always matches the source given
  in `from`.

  Similarly, if you are interested only on the last binding
  (or the last bindings) in a query, you can use `...` to
  specify "all bindings before" and match on the last one.

  For instance, imagine you wrote:

      posts_with_comments =
        from p in query, join: c in Comment, on: c.post_id == p.id

  And now we want to make sure to return both the post title
  and the comment body. Although we may not know how many
  bindings there are in the query, we are sure posts is the
  first binding and comments are the last one, so we can write:

      from [p, ..., c] in posts_with_comments, select: {p.title, c.body}

  In other words, `...` will include all the binding between the
  first and the last, which may be no binding at all, one or many.

  ### Named bindings

  Another option for flexibly building queries with joins are
  named bindings. Coming back to the previous example, provided
  we bind a join to a concrete name:

      posts_with_comments =
        from p in query,
          join: c in Comment, as: :comment, on: c.post_id == p.id

  We can refer to it by that name using a following form of
  bindings list:

      from [p, comment: c] in posts_with_comments, select: {p.title, c.body}

  This approach lets us not worry about keeping track of the position
  of the bindings when composing the query.

  What's more, a name can be assigned to the first binding as well:

      from p in Post, as: :post

  Only atoms are accepted for binding names. Named binding references
  are expected to be placed in the tail position of the bindings list.

  ### Bindingless operations

  Although bindings are extremely useful when working with joins,
  they are not necessary when the query has only the `from` clause.
  For such cases, Ecto supports a way for building queries
  without specifying the binding:

      from Post,
        where: [category: "fresh and new"],
        order_by: [desc: :published_at],
        select: [:id, :title, :body]

  The query above will select all posts with category "fresh and new",
  order by the most recently published, and return Post structs with
  only the id, title and body fields set. It is equivalent to:

      from p in Post,
        where: p.category == "fresh and new",
        order_by: [desc: p.published_at],
        select: struct(p, [:id, :title, :body])

  One advantage of bindingless queries is that they are data-driven
  and therefore useful for dynamically building queries. For example,
  the query above could also be written as:

      where = [category: "fresh and new"]
      order_by = [desc: :published_at]
      select = [:id, :title, :body]
      from Post, where: ^where, order_by: ^order_by, select: ^select

  This feature is very useful when queries need to be built based
  on some user input, like web search forms, CLIs and so on.

  ## Fragments

  If you need an escape hatch, Ecto provides fragments
  (see `Ecto.Query.API.fragment/1`) to inject SQL (and non-SQL)
  fragments into queries.

  For example, to get all posts while running the "lower(?)"
  function in the database where `p.title` is interpolated
  in place of `?`, one can write:

      from p in Post,
        where: is_nil(p.published_at) and
               fragment("lower(?)", p.title) == ^title

  Also, most adapters provide direct APIs for queries, like
  `Ecto.Adapters.SQL.query/4`, allowing developers to
  completely bypass Ecto queries.

  ## Macro API

  In all examples so far we have used the **keywords query syntax** to
  create a query:

      import Ecto.Query
      from u in "users", where: u.age > 18, select: u.name

  Due to the prevalence of the pipe operator in Elixir, Ecto also supports
  a pipe-based syntax:

      "users"
      |> where([u], u.age > 18)
      |> select([u], u.name)

  The keyword-based and pipe-based examples are equivalent. The downside
  of using macros is that the binding must be specified for every operation.
  However, since keyword-based and pipe-based examples are equivalent, the
  bindingless syntax also works for macros:

      "users"
      |> where([u], u.age > 18)
      |> select([:name])

  Such allows developers to write queries using bindings only in more
  complex query expressions.

  This module documents each of those macros, providing examples in
  both the keywords query and pipe expression formats.

  ## Query Prefix

  It is possible to set a prefix for the queries. For Postgres users,
  this will specify the schema where the table is located, while for
  MySQL users this will specify the database where the table is
  located.  When no prefix is set, Postgres queries are assumed to be
  in the public schema, while MySQL queries are assumed to be in the
  database set in the config for the repo.

  The query prefix may be set either for the whole query or on each
  individual `from` and `join` expression. If a `prefix` is not given
  to a `from` or a `join`, the prefix of the schema given to the `from`
  or `join` is used. The query prefix is used only if none of the above
  are declared.

  Let's see some examples. To see the query prefix globally, the simplest
  mechanism is to pass an option to the repository operation:

      results = Repo.all(query, prefix: "accounts")

  You may also set the prefix for the whole query by setting the prefix field:

      results =
        query # May be User or an Ecto.Query itself
        |> Ecto.Queryable.to_query
        |> Map.put(:prefix, "accounts")
        |> Repo.all()

  Setting the prefix in the query changes the default prefix of all `from`
  and `join` expressions. You can override the query prefix by either setting
  the `@schema_prefix` in your schema definitions or by passing the prefix
  option:

      from u in User,
        prefix: "accounts",
        join: p in assoc(u, :posts),
        prefix: "public"

  Overall, here is the prefix lookup precedence:

    1. The `:prefix` option given to `from`/`join` has the highest precedence
    2. Then it falls back to the `@schema_prefix` attribute declared in the schema
      given to `from`/`join`
    3. Then it falls back to the query prefix

  The prefixes set in the query will be preserved when loading data.
  """

  defstruct [prefix: nil, sources: nil, from: nil, joins: [], aliases: %{}, wheres: [], select: nil,
             order_bys: [], limit: nil, offset: nil, group_bys: [], combinations: [], updates: [],
             havings: [], preloads: [], assocs: [], distinct: nil, lock: nil, windows: [],
             with_ctes: nil]

  defmodule FromExpr do
    @moduledoc false
    defstruct [:source, :as, :prefix, hints: []]
  end

  defmodule DynamicExpr do
    @moduledoc false
    defstruct [:fun, :binding, :file, :line]
  end

  defmodule QueryExpr do
    @moduledoc false
    defstruct [:expr, :file, :line, params: []]
  end

  defmodule BooleanExpr do
    @moduledoc false
    defstruct [:op, :expr, :file, :line, params: []]
  end

  defmodule SelectExpr do
    @moduledoc false
    defstruct [:expr, :file, :line, :fields, params: [], take: %{}]
  end

  defmodule JoinExpr do
    @moduledoc false
    defstruct [:qual, :source, :on, :file, :line, :assoc, :as, :ix, :prefix, params: [], hints: []]
  end

  defmodule WithExpr do
    @moduledoc false
    defstruct [recursive: false, queries: []]
  end

  defmodule Tagged do
    @moduledoc false
    # * value is the tagged value
    # * tag is the directly tagged value, like Ecto.UUID
    # * type is the underlying tag type, like :string
    defstruct [:value, :tag, :type]
  end

  @type t :: %__MODULE__{}
  @opaque dynamic :: %DynamicExpr{}

  alias Ecto.Query.Builder

  @doc """
  Builds a dynamic query expression.

  Dynamic query expressions allows developers to build queries
  expression bit by bit so they are later interpolated in a query.

  ## Examples

  For example, imagine you have a set of conditions you want to
  build your query on:

      conditions = false

      conditions =
        if params["is_public"] do
          dynamic([p], p.is_public or ^conditions)
        else
          conditions
        end

      conditions =
        if params["allow_reviewers"] do
          dynamic([p, a], a.reviewer == true or ^conditions)
        else
          conditions
        end

      from query, where: ^conditions

  In the example above, we were able to build the query expressions
  bit by bit, using different bindings, and later interpolate it all
  at once inside the query.

  A dynamic expression can always be interpolated inside another dynamic
  expression and into the constructs described below.

  ## `where`, `having` and a `join`'s `on'

  The `dynamic` macro can be interpolated at the root of a `where`,
  `having` or a `join`'s `on`.

  For example, assuming the `conditions` variable defined in the
  previous section, the following is forbidden because it is not
  at the root of a `where`:

      from q in query, where: q.some_condition and ^conditions

  Fortunately that's easily solvable by simply rewriting it to:

      conditions = dynamic([q], q.some_condition and ^conditions)
      from query, where: ^conditions

  ## `order_by`

  Dynamics can be interpolated inside keyword lists at the root of
  `order_by`. For example, you can write:

      order_by = [
        asc: :some_field,
        desc: dynamic([p], fragment("?>>?", p.another_field, "json_key"))
      ]

      from query, order_by: ^order_by

  Dynamics are also supported in `order_by/2` clauses inside `windows/2`.

  As with `where` and friends, it is not possible to pass dynamics
  outside of a root. For example, this won't work:

      from query, order_by: [asc: ^dynamic(...)]

  But this will:

      from query, order_by: ^[asc: dynamic(...)]

  ## `group_by`

  Dynamics can be interpolated inside keyword lists at the root of
  `group_by`. For example, you can write:

      group_by = [
        :some_field,
        dynamic([p], fragment("?>>?", p.another_field, "json_key"))
      ]

      from query, group_by: ^group_by

  Dynamics are also supported in `partition_by/2` clauses inside `windows/2`.

  As with `where` and friends, it is not possible to pass dynamics
  outside of a root. For example, this won't work:

      from query, group_by: [:some_field, ^dynamic(...)]

  But this will:

      from query, order_by: ^[:some_field, dynamic(...)]

  ## Updates

  Dynamic is also supported inside updates, for example:

      updates = [
        set: [average: dynamic([p], p.sum / p.count)]
      ]

      from query, update: ^updates
  """
  defmacro dynamic(binding \\ [], expr) do
    Builder.Dynamic.build(binding, expr, __CALLER__)
  end

  @doc """
  Defines windows which can be used with `Ecto.Query.WindowAPI`.

  Receives a keyword list where keys are names of the windows
  and values are a keyword list with window expressions.

  ## Examples

      # Compare each employee's salary with the average salary in his or her department
      from e in Employee,
        select: {e.depname, e.empno, e.salary, over(avg(e.salary), :department)},
        windows: [department: [partition_by: e.depname]]

  In the example above, we get the average salary per department.
  `:department` is the window name, partitioned by `e.depname`
  and `avg/1` is the window function. For more information
  on windows functions, see `Ecto.Query.WindowAPI`.

  ## Window expressions

  The following keys are allowed when specifying a window.

  ### :partition_by

  A list of fields to partition the window by, for example:

      windows: [department: [partition_by: e.depname]]

  A list of atoms can also be interpolated for dynamic partitioning:

      fields = [:depname, :year]
      windows: [dynamic_window: [partition_by: ^fields]]

  ### :order_by

  A list of fields to order the window by, for example:

      windows: [ordered_names: [order_by: e.name]]

  It works exactly as the keyword query version of `order_by/3`.

  ### :frame

  A fragment which defines the frame for window functions.

  ## Examples

      # compare each employee's salary for each month with his average salary for previous 3 months
      from p in Payroll,
        select: {p.empno, p.date, p.salary, over(avg(p.salary), :prev_months)},
        windows: [prev_months: [partition_by: p.empno, order_by: p.date, frame: fragment("ROWS 3 PRECEDING EXCLUDE CURRENT ROW")]]

  """
  defmacro windows(query, binding \\ [], expr) do
    Builder.Windows.build(query, binding, expr, __CALLER__)
  end

  @doc """
  Converts a query into a subquery.

  If a subquery is given, returns the subquery itself.
  If any other value is given, it is converted to a query via
  `Ecto.Queryable` and wrapped in the `Ecto.SubQuery` struct.

  Subqueries are currently only supported in the `from`
  and `join` fields.

  ## Examples

      # Get the average salary of the top 10 highest salaries
      query = from Employee, order_by: [desc: :salary], limit: 10
      from e in subquery(query), select: avg(e.salary)

  A prefix can be specified for a subquery, similar to standard repo operations:

      query = from Employee, order_by: [desc: :salary], limit: 10
      from e in subquery(query, prefix: "my_prefix"), select: avg(e.salary)

  Although subqueries are not allowed in WHERE expressions,
  most subqueries in WHERE expression can be rewritten as JOINs.
  Imagine you want to write this query:

      UPDATE posts
        SET sync_started_at = $1
        WHERE id IN (
          SELECT id FROM posts
            WHERE synced = false AND (sync_started_at IS NULL OR sync_started_at < $1)
            LIMIT $2
        )

  If you attempt to write it as `where: p.id in ^subquery(foo)`,
  Ecto won't accept such query. However, the subquery above can be
  written as a JOIN, which is supported by Ecto. The final Ecto
  query will look like this:

      subset_query = from(p in Post,
        where: p.synced == false and
                 (is_nil(p.sync_started_at) or p.sync_started_at < ^min_sync_started_at),
        limit: ^batch_size
      )

      Repo.update_all(
        from(p in Post, join: s in subquery(subset_query), on: s.id == p.id),
        set: [sync_started_at: NaiveDateTime.utc_now()]
      )

  """
  def subquery(query, opts \\ []) do
    subquery = wrap_in_subquery(query)
    case Keyword.fetch(opts, :prefix) do
      {:ok, prefix} when is_binary(prefix) or is_nil(prefix) -> put_in(subquery.query.prefix, prefix)
      :error -> subquery
    end
  end

  defp wrap_in_subquery(%Ecto.SubQuery{} = subquery), do: subquery
  defp wrap_in_subquery(%Ecto.Query{} = query), do: %Ecto.SubQuery{query: query}
  defp wrap_in_subquery(queryable), do: %Ecto.SubQuery{query: Ecto.Queryable.to_query(queryable)}

  @joins [:join, :inner_join, :cross_join, :left_join, :right_join, :full_join,
          :inner_lateral_join, :left_lateral_join]

  @doc """
  Resets a previously set field on a query.

  It can reset many fields except the query source (`from`). When excluding
  a `:join`, it will remove *all* types of joins. If you prefer to remove a
  single type of join, please see paragraph below.

  ## Examples

      Ecto.Query.exclude(query, :join)
      Ecto.Query.exclude(query, :where)
      Ecto.Query.exclude(query, :order_by)
      Ecto.Query.exclude(query, :group_by)
      Ecto.Query.exclude(query, :having)
      Ecto.Query.exclude(query, :distinct)
      Ecto.Query.exclude(query, :select)
      Ecto.Query.exclude(query, :combinations)
      Ecto.Query.exclude(query, :with_ctes)
      Ecto.Query.exclude(query, :limit)
      Ecto.Query.exclude(query, :offset)
      Ecto.Query.exclude(query, :lock)
      Ecto.Query.exclude(query, :preload)

  You can also remove specific joins as well such as `left_join` and
  `inner_join`:

      Ecto.Query.exclude(query, :inner_join)
      Ecto.Query.exclude(query, :cross_join)
      Ecto.Query.exclude(query, :left_join)
      Ecto.Query.exclude(query, :right_join)
      Ecto.Query.exclude(query, :full_join)
      Ecto.Query.exclude(query, :inner_lateral_join)
      Ecto.Query.exclude(query, :left_lateral_join)

  However, keep in mind that if a join is removed and its bindings
  were referenced elsewhere, the bindings won't be removed, leading
  to a query that won't compile.
  """
  def exclude(%Ecto.Query{} = query, field), do: do_exclude(query, field)
  def exclude(query, field), do: do_exclude(Ecto.Queryable.to_query(query), field)

  defp do_exclude(%Ecto.Query{} = query, :join) do
    %{query | joins: [], aliases: Map.take(query.aliases, [query.from.as])}
  end
  defp do_exclude(%Ecto.Query{} = query, join_keyword) when join_keyword in @joins do
    qual = join_qual(join_keyword)
    {excluded, remaining} = Enum.split_with(query.joins, &(&1.qual == qual))
    aliases =  Map.drop(query.aliases, Enum.map(excluded, & &1.as))
    %{query | joins: remaining, aliases: aliases}
  end
  defp do_exclude(%Ecto.Query{} = query, :where), do: %{query | wheres: []}
  defp do_exclude(%Ecto.Query{} = query, :order_by), do: %{query | order_bys: []}
  defp do_exclude(%Ecto.Query{} = query, :group_by), do: %{query | group_bys: []}
  defp do_exclude(%Ecto.Query{} = query, :combinations), do: %{query | combinations: []}
  defp do_exclude(%Ecto.Query{} = query, :with_ctes), do: %{query | with_ctes: nil}
  defp do_exclude(%Ecto.Query{} = query, :having), do: %{query | havings: []}
  defp do_exclude(%Ecto.Query{} = query, :distinct), do: %{query | distinct: nil}
  defp do_exclude(%Ecto.Query{} = query, :select), do: %{query | select: nil}
  defp do_exclude(%Ecto.Query{} = query, :limit), do: %{query | limit: nil}
  defp do_exclude(%Ecto.Query{} = query, :offset), do: %{query | offset: nil}
  defp do_exclude(%Ecto.Query{} = query, :lock), do: %{query | lock: nil}
  defp do_exclude(%Ecto.Query{} = query, :preload), do: %{query | preloads: [], assocs: []}

  @doc """
  Creates a query.

  It can either be a keyword query or a query expression.

  If it is a keyword query the first argument must be
  either an `in` expression, or a value that implements
  the `Ecto.Queryable` protocol. If the query needs a
  reference to the data source in any other part of the
  expression, then an `in` must be used to create a reference
  variable. The second argument should be a keyword query
  where the keys are expression types and the values are
  expressions.

  If it is a query expression the first argument must be
  a value that implements the `Ecto.Queryable` protocol
  and the second argument the expression.

  ## Keywords example

      from(c in City, select: c)

  ## Expressions example

      City |> select([c], c)

  ## Examples

      def paginate(query, page, size) do
        from query,
          limit: ^size,
          offset: ^((page-1) * size)
      end

  The example above does not use `in` because `limit` and `offset`
  do not require a reference to the data source. However, extending
  the query with a where expression would require the use of `in`:

      def published(query) do
        from p in query, where: not(is_nil(p.published_at))
      end

  Notice we have created a `p` variable to reference the query's
  original data source. This assumes that the original query
  only had one source. When the given query has more than one source,
  positonal or named bindings may be used to access the additional sources.

      def published_multi(query) do
        from [p,o] in query,
        where: not(is_nil(p.published_at)) and not(is_nil(o.published_at))
      end

  Note the variables `p` and `o` can be named whatever you like
  as they have no importance in the query sent to the database.
  """
  defmacro from(expr, kw \\ []) do
    unless Keyword.keyword?(kw) do
      raise ArgumentError, "second argument to `from` must be a compile time keyword list"
    end

    {kw, as, prefix, hints} = collect_as_and_prefix_and_hints(kw, nil, nil, nil)
    {quoted, binds, count_bind} = Builder.From.build(expr, __CALLER__, as, prefix, hints)
    from(kw, __CALLER__, count_bind, quoted, to_query_binds(binds))
  end

  @from_join_opts [:as, :prefix, :hints]
  @no_binds [:lock, :union, :union_all, :except, :except_all, :intersect, :intersect_all]
  @binds [:where, :or_where, :select, :distinct, :order_by, :group_by, :windows] ++
           [:having, :or_having, :limit, :offset, :preload, :update, :select_merge, :with_ctes]

  defp from([{type, expr}|t], env, count_bind, quoted, binds) when type in @binds do
    # If all bindings are integer indexes keep AST Macro expandable to %Query{},
    # otherwise ensure that quoted code is evaluated before macro call
    quoted =
      if Enum.all?(binds, fn {_, value} -> is_integer(value) end) do
        quote do
          Ecto.Query.unquote(type)(unquote(quoted), unquote(binds), unquote(expr))
        end
      else
        quote do
          query = unquote(quoted)
          Ecto.Query.unquote(type)(query, unquote(binds), unquote(expr))
        end
      end

    from(t, env, count_bind, quoted, binds)
  end

  defp from([{type, expr}|t], env, count_bind, quoted, binds) when type in @no_binds do
    quoted =
      quote do
        Ecto.Query.unquote(type)(unquote(quoted), unquote(expr))
      end

    from(t, env, count_bind, quoted, binds)
  end

  defp from([{join, expr}|t], env, count_bind, quoted, binds) when join in @joins do
    qual = join_qual(join)
    {t, on, as, prefix, hints} = collect_on(t, nil, nil, nil, nil)

    {quoted, binds, count_bind} =
      Builder.Join.build(quoted, qual, binds, expr, count_bind, on, as, prefix, hints, env)

    from(t, env, count_bind, quoted, to_query_binds(binds))
  end

  defp from([{:on, _value}|_], _env, _count_bind, _quoted, _binds) do
    Builder.error! "`on` keyword must immediately follow a join"
  end

  defp from([{key, _value}|_], _env, _count_bind, _quoted, _binds) when key in @from_join_opts do
    Builder.error! "`#{key}` keyword must immediately follow a from/join"
  end

  defp from([{key, _value}|_], _env, _count_bind, _quoted, _binds) do
    Builder.error! "unsupported #{inspect key} in keyword query expression"
  end

  defp from([], _env, _count_bind, quoted, _binds) do
    quoted
  end

  defp to_query_binds(binds) do
    for {k, v} <- binds, do: {{k, [], nil}, v}
  end

  defp join_qual(:join), do: :inner
  defp join_qual(:full_join), do: :full
  defp join_qual(:left_join), do: :left
  defp join_qual(:right_join), do: :right
  defp join_qual(:inner_join), do: :inner
  defp join_qual(:cross_join), do: :cross
  defp join_qual(:left_lateral_join), do: :left_lateral
  defp join_qual(:inner_lateral_join), do: :inner_lateral

  defp collect_on([{key, _} | _] = t, on, as, prefix, hints) when key in @from_join_opts do
    {t, as, prefix, hints} = collect_as_and_prefix_and_hints(t, as, prefix, hints)
    collect_on(t, on, as, prefix, hints)
  end

  defp collect_on([{:on, on} | t], nil, as, prefix, hints),
    do: collect_on(t, on, as, prefix, hints)
  defp collect_on([{:on, expr} | t], on, as, prefix, hints),
    do: collect_on(t, {:and, [], [on, expr]}, as, prefix, hints)
  defp collect_on(t, on, as, prefix, hints),
    do: {t, on, as, prefix, hints}

  defp collect_as_and_prefix_and_hints([{:as, as} | t], nil, prefix, hints),
    do: collect_as_and_prefix_and_hints(t, as, prefix, hints)
  defp collect_as_and_prefix_and_hints([{:as, _} | _], _, _, _),
    do: Builder.error! "`as` keyword was given more than once to the same from/join"
  defp collect_as_and_prefix_and_hints([{:prefix, prefix} | t], as, nil, hints),
    do: collect_as_and_prefix_and_hints(t, as, prefix, hints)
  defp collect_as_and_prefix_and_hints([{:prefix, _} | _], _, _, _),
    do: Builder.error! "`prefix` keyword was given more than once to the same from/join"
  defp collect_as_and_prefix_and_hints([{:hints, hints} | t], as, prefix, nil),
    do: collect_as_and_prefix_and_hints(t, as, prefix, hints)
  defp collect_as_and_prefix_and_hints([{:hints, _} | _], _, _, _),
    do: Builder.error! "`hints` keyword was given more than once to the same from/join"
  defp collect_as_and_prefix_and_hints(t, as, prefix, hints),
    do: {t, as, prefix, hints}

  @doc """
  A join query expression.

  Receives a source that is to be joined to the query and a condition for
  the join. The join condition can be any expression that evaluates
  to a boolean value. The join is by default an inner join, the qualifier
  can be changed by giving the atoms: `:inner`, `:left`, `:right`, `:cross`,
  `:full`, `:inner_lateral` or `:left_lateral`. For a keyword query the `:join`
  keyword can be changed to: `:inner_join`, `:left_join`, `:right_join`,
  `:cross_join`, `:full_join`, `:inner_lateral_join` or `:left_lateral_join`.

  Currently it is possible to join on:

    * an `Ecto.Schema`, such as `p in Post`
    * an interpolated Ecto query with zero or more where clauses,
      such as `c in ^(from "posts", where: [public: true])`
    * an association, such as `c in assoc(post, :comments)`
    * a subquery, such as `c in subquery(another_query)`
    * a query fragment, such as `c in fragment("SOME COMPLEX QUERY")`,
      see "Joining with fragments" below.

  ## Options

  Each join accepts the following options:

    * `:on` - a query expression or keyword list to filter the join
    * `:as` - a named binding for the join
    * `:prefix` - the prefix to be used for the join when issuing a database query
    * `:hints` - a string or a list of strings to be used as database hints

  In the keyword query syntax, those options must be given immediately
  after the join. In the expression syntax, the options are given as
  the fifth argument.

  ## Keywords examples

      from c in Comment,
        join: p in Post,
        on: p.id == c.post_id,
        select: {p.title, c.text}

      from p in Post,
        left_join: c in assoc(p, :comments),
        select: {p, c}

  Keywords can also be given or interpolated as part of `on`:

      from c in Comment,
        join: p in Post,
        on: [id: c.post_id],
        select: {p.title, c.text}

  Any key in `on` will apply to the currently joined expression.

  It is also possible to interpolate an Ecto query on the right side
  of `in`. For example, the query above can also be written as:

      posts = Post
      from c in Comment,
        join: p in ^posts,
        on: [id: c.post_id],
        select: {p.title, c.text}

  The above is specially useful to dynamically join on existing
  queries, for example, to dynamically choose a source, or by
  choosing between public posts or posts that have been recently
  published:

      posts =
        if params["drafts"] do
          from p in Post, where: [drafts: true]
        else
          from p in Post, where: [public: true]
        end

      from c in Comment,
        join: p in ^posts, on: [id: c.post_id],
        select: {p.title, c.text}

  Only simple queries with `where` expressions can be interpolated
  in join.

  ## Expressions examples

      Comment
      |> join(:inner, [c], p in Post, on: c.post_id == p.id)
      |> select([c, p], {p.title, c.text})

      Post
      |> join(:left, [p], c in assoc(p, :comments))
      |> select([p, c], {p, c})

      Post
      |> join(:left, [p], c in Comment, on: c.post_id == p.id and c.is_visible == true)
      |> select([p, c], {p, c})

  ## Joining with fragments

  When you need to join on a complex query, Ecto supports fragments in joins:

      Comment
      |> join(:inner, [c], p in fragment("SOME COMPLEX QUERY", c.id, ^some_param))

  Although using fragments in joins is discouraged in favor of Ecto
  Query syntax, they are necessary when writing lateral joins as
  lateral joins require a subquery that refer to previous bindings:

      Game
      |> join(:inner_lateral, [g], gs in fragment("SELECT * FROM games_sold AS gs WHERE gs.game_id = ? ORDER BY gs.sold_on LIMIT 2", g.id))
      |> select([g, gs], {g.name, gs.sold_on})

  Note that the `join` does not automatically wrap the fragment in
  parentheses, since some expressions require parens and others
  require no parens. Therefore, in cases such as common table
  expressions, you will have to explicitly wrap the fragment content
  in parens.

  ## Hints

  `from` and `join` also support index hints, as found in databases such as
  [MySQL](https://dev.mysql.com/doc/refman/8.0/en/index-hints.html) and
  [MSSQL](https://docs.microsoft.com/en-us/sql/t-sql/queries/hints-transact-sql-table?view=sql-server-2017).

  For example, a developer using MySQL may write:

      from p in Post,
        join: c in Comment,
        hints: ["USE INDEX FOO", "USE INDEX BAR"],
        where: p.id == c.post_id,
        select: c

  Keep in mind you want to use hints rarely, so don't forget to read the database
  disclaimers about such functionality.
  """
  @join_opts [:on | @from_join_opts]

  defmacro join(query, qual, binding \\ [], expr, opts \\ [])
  defmacro join(query, qual, binding, expr, opts)
           when is_list(binding) and is_list(opts) do
    {t, on, as, prefix, hints} = collect_on(opts, nil, nil, nil, nil)

    with [{key, _} | _] <- t do
      raise ArgumentError, "invalid option `#{key}` passed to Ecto.Query.join/5, " <>
                             "valid options are: #{inspect(@join_opts)}"
    end

    query
    |> Builder.Join.build(qual, binding, expr, nil, on, as, prefix, hints, __CALLER__)
    |> elem(0)
  end

  defmacro join(_query, _qual, binding, _expr, opts) when is_list(opts) do
    raise ArgumentError, "invalid binding passed to Ecto.Query.join/5, should be " <>
                           "list of variables, got: #{Macro.to_string(binding)}"
  end

  @doc """
  A common table expression (CTE) also known as WITH expression.

  `name` must be a compile-time literal string that is being used
  as the table name to join the CTE in the main query or in the
  recursive CTE.

  **IMPORTANT!** Beware of using CTEs. In raw SQL, CTEs can be
  used as a mechanism to organize queries, but said mechanism
  has no purpose in Ecto since Ecto queries are composable by
  definition. In other words, if you need to break a large query
  into parts, use all of the functionality in Elixir and in this
  module to struture your code. Furthermore, breaking a query
  into CTEs can negatively impact performance, as the database
  may not optimize efficiently across CTEs. The main use case
  for CTEs in Ecto is to provide recursive definitions, which
  we outline in the following section. Non-recursive CTEs can
  often be written as joins or subqueries, which provide better
  performance.

  ## Options

    * `:as` – the CTE query itself or a fragment

  ## Recursive CTEs

  Use `recursive_ctes/2` to enable recursive mode for CTEs.

  In the CTE query itself use the same table name to leverage
  recursion that has been passed to the `name` argument. Make sure
  to write a stop condition to avoid infinite recursion loop.
  Generally speaking, you should only use CTEs in Ecto for
  writing recursive queries.

  ## Expression examples

  Products and their category names for breadcrumbs:

      category_tree_initial_query =
        Category
        |> where([c], is_nil(c.parent_id))

      category_tree_recursion_query =
        Category
        |> join(:inner, [c], ct in "category_tree", on: c.parent_id == ct.id)

      category_tree_query =
        category_tree_initial_query
        |> union_all(^category_tree_recursion_query)

      Product
      |> recursive_ctes(true)
      |> with_cte("category_tree", as: ^category_tree_query)
      |> join(:left, [p], c in "category_tree", on: c.id == p.category_id)
      |> group_by([p], p.id)
      |> select([p, c], %{p | category_names: fragment("ARRAY_AGG(?)", c.name)})

  It's possible to cast CTE result rows as Ecto structs:

      {"category_tree", Category}
      |> recursive_ctes(true)
      |> with_cte("category_tree", as: ^category_tree_query)
      |> join(:left, [c], p in assoc(c, :products))
      |> group_by([c], c.id)
      |> select([c, p], %{c | products_count: count(p.id)})

  It's also possible to pass a raw SQL fragment:

      @raw_sql_category_tree \"""
      SELECT * FROM categories WHERE c.parent_id IS NULL
      UNION ALL
      SELECT * FROM categories AS c, category_tree AS ct WHERE ct.id = c.parent_id
      \"""

      Product
      |> recursive_ctes(true)
      |> with_cte("category_tree", as: fragment(@raw_sql_category_tree))
      |> join(:inner, [p], c in "category_tree", on: c.id == p.category_id)

  Keyword syntax is not supported for this feature.

  ## Limitation: CTEs on schemas wth source fields

  Ecto allows developers to say that a table in their Ecto schema
  map to a different column in their database:

      field :group_id, :integer, source: :iGroupId

  At the moment, using a schema with source fields in CTE may emit
  invalid queries. If you are running into such scenarios, your best
  option is to use a fragment as your CTE.
  """
  defmacro with_cte(query, name, as: with_query) do
    Builder.CTE.build(query, name, with_query, __CALLER__)
  end

  @doc """
  Enables or disables recursive mode for CTEs.

  According to the SQL standard it affects all CTEs in the query, not individual ones.

  See `with_cte/3` on example of how to build a query with a recursive CTE.
  """
  def recursive_ctes(%__MODULE__{with_ctes: with_expr} = query, value) when is_boolean(value) do
    with_expr = with_expr || %WithExpr{}
    with_expr = %{with_expr | recursive: value}
    %{query | with_ctes: with_expr}
  end

  def recursive_ctes(queryable, value) do
    recursive_ctes(Ecto.Queryable.to_query(queryable), value)
  end

  @doc """
  A select query expression.

  Selects which fields will be selected from the schema and any transformations
  that should be performed on the fields. Any expression that is accepted in a
  query can be a select field.

  Select also allows each expression to be wrapped in lists, tuples or maps as
  shown in the examples below. A full schema can also be selected.

  There can only be one select expression in a query, if the select expression
  is omitted, the query will by default select the full schema. If select is
  given more than once, an error is raised. Use `exclude/2` if you would like
  to remove a previous select for overriding or see `select_merge/3` for a
  limited version of `select` that is composable and can be called multiple
  times.

  `select` also accepts a list of atoms where each atom refers to a field in
  the source to be selected.

  ## Keywords examples

      from(c in City, select: c) # returns the schema as a struct
      from(c in City, select: {c.name, c.population})
      from(c in City, select: [c.name, c.county])
      from(c in City, select: %{n: c.name, answer: 42})
      from(c in City, select: %{c | alternative_name: c.name})
      from(c in City, select: %Data{name: c.name})

  It is also possible to select a struct and limit the returned
  fields at the same time:

      from(City, select: [:name])

  The syntax above is equivalent to:

      from(city in City, select: struct(city, [:name]))

  You can also write:

      from(city in City, select: map(city, [:name]))

  If you want a map with only the selected fields to be returned.
  For more information, read the docs for `Ecto.Query.API.struct/2`
  and `Ecto.Query.API.map/2`.

  ## Expressions examples

      City |> select([c], c)
      City |> select([c], {c.name, c.country})
      City |> select([c], %{"name" => c.name})
      City |> select([:name])
      City |> select([c], struct(c, [:name]))
      City |> select([c], map(c, [:name]))

  """
  defmacro select(query, binding \\ [], expr) do
    Builder.Select.build(:select, query, binding, expr, __CALLER__)
  end

  @doc """
  Mergeable select query expression.

  This macro is similar to `select/3` except it may be specified
  multiple times as long as every entry is a map. This is useful
  for merging and composing selects. For example:

      query = from p in Post, select: %{}

      query =
        if include_title? do
          from p in query, select_merge: %{title: p.title}
        else
          query
        end

      query =
        if include_visits? do
          from p in query, select_merge: %{visits: p.visits}
        else
          query
        end

  In the example above, the query is built little by little by merging
  into a final map. If both conditions above are true, the final query
  would be equivalent to:

      from p in Post, select: %{title: p.title, visits: p.visits}

  If `:select_merge` is called and there is no value selected previously,
  it will default to the source, `p` in the example above.

  The argument given to `:select_merge` must always be a map. The value
  being merged on must be a struct or a map. If it is a struct, the fields
  merged later on must be part of the struct, otherwise an error is raised.

  `select_merge` cannot be used to set fields in associations, as
  associations are always loaded later, overriding any previous value.
  """
  defmacro select_merge(query, binding \\ [], expr) do
    Builder.Select.build(:merge, query, binding, expr, __CALLER__)
  end

  @doc """
  A distinct query expression.

  When true, only keeps distinct values from the resulting
  select expression.

  If supported by your database, you can also pass query expressions
  to distinct and it will generate a query with DISTINCT ON. In such
  cases, `distinct` accepts exactly the same expressions as `order_by`
  and any `distinct` expression will be automatically prepended to the
  `order_by` expressions in case there is any `order_by` expression.

  ## Keywords examples

      # Returns the list of different categories in the Post schema
      from(p in Post, distinct: true, select: p.category)

      # If your database supports DISTINCT ON(),
      # you can pass expressions to distinct too
      from(p in Post,
         distinct: p.category,
         order_by: [p.date])

      # The DISTINCT ON() also supports ordering similar to ORDER BY.
      from(p in Post,
         distinct: [desc: p.category],
         order_by: [p.date])

      # Using atoms
      from(p in Post, distinct: :category, order_by: :date)

  ## Expressions example

      Post
      |> distinct(true)
      |> order_by([p], [p.category, p.author])

  """
  defmacro distinct(query, binding \\ [], expr) do
    Builder.Distinct.build(query, binding, expr, __CALLER__)
  end

  @doc """
  An AND where query expression.

  `where` expressions are used to filter the result set. If there is more
  than one where expression, they are combined with an `and` operator. All
  where expressions have to evaluate to a boolean value.

  `where` also accepts a keyword list where the field given as key is going to
  be compared with the given value. The fields will always refer to the source
  given in `from`.

  ## Keywords example

      from(c in City, where: c.country == "Sweden")
      from(c in City, where: [country: "Sweden"])

  It is also possible to interpolate the whole keyword list, allowing you to
  dynamically filter the source:

      filters = [country: "Sweden"]
      from(c in City, where: ^filters)

  ## Expressions example

      City |> where([c], c.country == "Sweden")
      City |> where(country: "Sweden")

  """
  defmacro where(query, binding \\ [], expr) do
    Builder.Filter.build(:where, :and, query, binding, expr, __CALLER__)
  end

  @doc """
  An OR where query expression.

  Behaves exactly the same as `where` except it combines with any previous
  expression by using an `OR`. All expressions have to evaluate to a boolean
  value.

  `or_where` also accepts a keyword list where each key is a field to be
  compared with the given value. Each key-value pair will be combined
  using `AND`, exactly as in `where`.

  ## Keywords example

      from(c in City, where: [country: "Sweden"], or_where: [country: "Brazil"])

  If interpolating keyword lists, the keyword list entries are combined
  using ANDs and joined to any existing expression with an OR:

      filters = [country: "USA", name: "New York"]
      from(c in City, where: [country: "Sweden"], or_where: ^filters)

  is equivalent to:

      from c in City, where: (c.country == "Sweden") or
                             (c.country == "USA" and c.name == "New York")

  The behaviour above is by design to keep the changes between `where`
  and `or_where` minimal. Plus, if you have a keyword list and you
  would like each pair to be combined using `or`, it can be easily done
  with `Enum.reduce/3`:

      filters = [country: "USA", is_tax_exempt: true]
      Enum.reduce(filters, City, fn {key, value}, query ->
        from q in query, or_where: field(q, ^key) == ^value
      end)

  which will be equivalent to:

      from c in City, or_where: (c.country == "USA"), or_where: c.is_tax_exempt == true

  ## Expressions example

      City |> where([c], c.country == "Sweden") |> or_where([c], c.country == "Brazil")

  """
  defmacro or_where(query, binding \\ [], expr) do
    Builder.Filter.build(:where, :or, query, binding, expr, __CALLER__)
  end

  @doc """
  An order by query expression.

  Orders the fields based on one or more fields. It accepts a single field
  or a list of fields. The default direction is ascending (`:asc`) and can be
  customized in a keyword list as one of the following:

    * `:asc`
    * `:asc_nulls_last`
    * `:asc_nulls_first`
    * `:desc`
    * `:desc_nulls_last`
    * `:desc_nulls_first`

  The `*_nulls_first` and `*_nulls_last` variants are not supported by all
  databases. While all databases default to ascending order, the choice of
  "nulls first" or "nulls last" is specific to each database implementation.

  `order_by` may be invoked or listed in a query many times. New expressions
  are always appended to the previous ones.

  `order_by` also accepts a list of atoms where each atom refers to a field in
  source or a keyword list where the direction is given as key and the field
  to order as value.

  ## Keywords examples

      from(c in City, order_by: c.name, order_by: c.population)
      from(c in City, order_by: [c.name, c.population])
      from(c in City, order_by: [asc: c.name, desc: c.population])

      from(c in City, order_by: [:name, :population])
      from(c in City, order_by: [asc: :name, desc_nulls_first: :population])

  A keyword list can also be interpolated:

      values = [asc: :name, desc_nulls_first: :population]
      from(c in City, order_by: ^values)

  A fragment can also be used:

      from c in City, order_by: [
        # a deterministic shuffled order
        fragment("? % ? DESC", c.id, ^modulus),
        desc: c.id,
      ]

  ## Expressions example

      City |> order_by([c], asc: c.name, desc: c.population)
      City |> order_by(asc: :name) # Sorts by the cities name

  """
  defmacro order_by(query, binding \\ [], expr)  do
    Builder.OrderBy.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A union query expression.

  Combines result sets of multiple queries. The `select` of each query
  must be exactly the same, with the same types in the same order.

  Union expression returns only unique rows as if each query returned
  distinct results. This may cause performance penalty. If you need
  just to combine multiple result sets without removing duplicate rows
  consider using `union_all/2`.

  Note that the operations `order_by`, `limit` and `offset` of the
  current `query` apply to the result of the union.

  ## Keywords example

      supplier_query = from s in Supplier, select: s.city
      from c in Customer, select: c.city, union: ^supplier_query

  ## Expressions example

      supplier_query = Supplier |> select([s], s.city)
      Customer |> select([c], c.city) |> union(^supplier_query)

  """
  defmacro union(query, other_query) do
    Builder.Combination.build(:union, query, other_query, __CALLER__)
  end

  @doc """
  A union all query expression.

  Combines result sets of multiple queries. The `select` of each query
  must be exactly the same, with the same types in the same order.

  Note that the operations `order_by`, `limit` and `offset` of the
  current `query` apply to the result of the union.

  ## Keywords example

      supplier_query = from s in Supplier, select: s.city
      from c in Customer, select: c.city, union_all: ^supplier_query

  ## Expressions example

      supplier_query = Supplier |> select([s], s.city)
      Customer |> select([c], c.city) |> union_all(^supplier_query)
  """
  defmacro union_all(query, other_query) do
    Builder.Combination.build(:union_all, query, other_query, __CALLER__)
  end

  @doc """
  An except (set difference) query expression.

  Takes the difference of the result sets of multiple queries. The
  `select` of each query must be exactly the same, with the same
  types in the same order.

  Except expression returns only unique rows as if each query returned
  distinct results. This may cause performance penalty. If you need
  just to take the difference of multiple result sets without
  removing duplicate rows consider using `except_all/2`.

  Note that the operations `order_by`, `limit` and `offset` of the
  current `query` apply to the result of the set difference.

  ## Keywords example

      supplier_query = from s in Supplier, select: s.city
      from c in Customer, select: c.city, except: ^supplier_query

  ## Expressions example

      supplier_query = Supplier |> select([s], s.city)
      Customer |> select([c], c.city) |> except(^supplier_query)
  """
  defmacro except(query, other_query) do
    Builder.Combination.build(:except, query, other_query, __CALLER__)
  end

  @doc """
  An except (set difference) query expression.

  Takes the difference of the result sets of multiple queries. The
  `select` of each query must be exactly the same, with the same
  types in the same order.

  Note that the operations `order_by`, `limit` and `offset` of the
  current `query` apply to the result of the set difference.

  ## Keywords example

      supplier_query = from s in Supplier, select: s.city
      from c in Customer, select: c.city, except_all: ^supplier_query

  ## Expressions example

      supplier_query = Supplier |> select([s], s.city)
      Customer |> select([c], c.city) |> except_all(^supplier_query)
  """
  defmacro except_all(query, other_query) do
    Builder.Combination.build(:except_all, query, other_query, __CALLER__)
  end

  @doc """
  An intersect query expression.

  Takes the overlap of the result sets of multiple queries. The
  `select` of each query must be exactly the same, with the same
  types in the same order.

  Intersect expression returns only unique rows as if each query returned
  distinct results. This may cause performance penalty. If you need
  just to take the intersection of multiple result sets without
  removing duplicate rows consider using `intersect_all/2`.

  Note that the operations `order_by`, `limit` and `offset` of the
  current `query` apply to the result of the set difference.

  ## Keywords example

      supplier_query = from s in Supplier, select: s.city
      from c in Customer, select: c.city, intersect: ^supplier_query

  ## Expressions example

      supplier_query = Supplier |> select([s], s.city)
      Customer |> select([c], c.city) |> intersect(^supplier_query)
  """
  defmacro intersect(query, other_query) do
    Builder.Combination.build(:intersect, query, other_query, __CALLER__)
  end

  @doc """
  An intersect query expression.

  Takes the overlap of the result sets of multiple queries. The
  `select` of each query must be exactly the same, with the same
  types in the same order.

  Note that the operations `order_by`, `limit` and `offset` of the
  current `query` apply to the result of the set difference.

  ## Keywords example

      supplier_query = from s in Supplier, select: s.city
      from c in Customer, select: c.city, intersect_all: ^supplier_query

  ## Expressions example

      supplier_query = Supplier |> select([s], s.city)
      Customer |> select([c], c.city) |> intersect_all(^supplier_query)
  """
  defmacro intersect_all(query, other_query) do
    Builder.Combination.build(:intersect_all, query, other_query, __CALLER__)
  end

  @doc """
  A limit query expression.

  Limits the number of rows returned from the result. Can be any expression but
  has to evaluate to an integer value and it can't include any field.

  If `limit` is given twice, it overrides the previous value.

  ## Keywords example

      from(u in User, where: u.id == ^current_user, limit: 1)

  ## Expressions example

      User |> where([u], u.id == ^current_user) |> limit(1)

  """
  defmacro limit(query, binding \\ [], expr) do
    Builder.LimitOffset.build(:limit, query, binding, expr, __CALLER__)
  end

  @doc """
  An offset query expression.

  Offsets the number of rows selected from the result. Can be any expression
  but it must evaluate to an integer value and it can't include any field.

  If `offset` is given twice, it overrides the previous value.

  ## Keywords example

      # Get all posts on page 4
      from(p in Post, limit: 10, offset: 30)

  ## Expressions example

      Post |> limit(10) |> offset(30)

  """
  defmacro offset(query, binding \\ [], expr) do
    Builder.LimitOffset.build(:offset, query, binding, expr, __CALLER__)
  end

  @doc ~S"""
  A lock query expression.

  Provides support for row-level pessimistic locking using
  `SELECT ... FOR UPDATE` or other, database-specific, locking clauses.
  `expr` can be any expression but has to evaluate to a boolean value or to a
  string and it can't include any fields.

  If `lock` is used more than once, the last one used takes precedence.

  Ecto also supports [optimistic
  locking](http://en.wikipedia.org/wiki/Optimistic_concurrency_control) but not
  through queries. For more information on optimistic locking, have a look at
  the `Ecto.Changeset.optimistic_lock/3` function

  ## Keywords example

      from(u in User, where: u.id == ^current_user, lock: "FOR SHARE NOWAIT")

  ## Expressions example

      User |> where(u.id == ^current_user) |> lock("FOR SHARE NOWAIT")

  """
  defmacro lock(query, expr) do
    Builder.Lock.build(query, expr, __CALLER__)
  end

  @doc ~S"""
  An update query expression.

  Updates are used to update the filtered entries. In order for
  updates to be applied, `c:Ecto.Repo.update_all/3` must be invoked.

  ## Keywords example

      from(u in User, update: [set: [name: "new name"]])

  ## Expressions example

      User |> update([u], set: [name: "new name"])
      User |> update(set: [name: "new name"])

  ## Interpolation

      new_name = "new name"
      from(u in User, update: [set: [name: ^new_name]])

      new_name = "new name"
      from(u in User, update: [set: [name: fragment("upper(?)", ^new_name)]])

  ## Operators

  The update expression in Ecto supports the following operators:

    * `set` - sets the given field in the table to the given value

          from(u in User, update: [set: [name: "new name"]])

    * `inc` - increments (or decrements if the value is negative) the given field in the table by the given value

          from(u in User, update: [inc: [accesses: 1]])

    * `push` - pushes (appends) the given value to the end of the array field

          from(u in User, update: [push: [tags: "cool"]])

    * `pull` - pulls (removes) the given value from the array field

          from(u in User, update: [pull: [tags: "not cool"]])

  """
  defmacro update(query, binding \\ [], expr) do
    Builder.Update.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A group by query expression.

  Groups together rows from the schema that have the same values in the given
  fields. Using `group_by` "groups" the query giving it different semantics
  in the `select` expression. If a query is grouped, only fields that were
  referenced in the `group_by` can be used in the `select` or if the field
  is given as an argument to an aggregate function.

  `group_by` also accepts a list of atoms where each atom refers to
  a field in source. For more complicated queries you can access fields
  directly instead of atoms.

  ## Keywords examples

      # Returns the number of posts in each category
      from(p in Post,
        group_by: p.category,
        select: {p.category, count(p.id)})

      # Using atoms
      from(p in Post, group_by: :category, select: {p.category, count(p.id)})

      # Using direct fields access
      from(p in Post,
        join: c in assoc(p, :category)
        group_by: [p.id, c.name])

  ## Expressions example

      Post |> group_by([p], p.category) |> select([p], count(p.id))

  """
  defmacro group_by(query, binding \\ [], expr) do
    Builder.GroupBy.build(query, binding, expr, __CALLER__)
  end

  @doc """
  An AND having query expression.

  Like `where`, `having` filters rows from the schema, but after the grouping is
  performed giving it the same semantics as `select` for a grouped query
  (see `group_by/3`). `having` groups the query even if the query has no
  `group_by` expression.

  ## Keywords example

      # Returns the number of posts in each category where the
      # average number of comments is above ten
      from(p in Post,
        group_by: p.category,
        having: avg(p.num_comments) > 10,
        select: {p.category, count(p.id)})

  ## Expressions example

      Post
      |> group_by([p], p.category)
      |> having([p], avg(p.num_comments) > 10)
      |> select([p], count(p.id))
  """
  defmacro having(query, binding \\ [], expr) do
    Builder.Filter.build(:having, :and, query, binding, expr, __CALLER__)
  end

  @doc """
  An OR having query expression.

  Like `having` but combines with the previous expression by using
  `OR`. `or_having` behaves for `having` the same way `or_where`
  behaves for `where`.

  ## Keywords example

      # Augment a previous group_by with a having condition.
      from(p in query, or_having: avg(p.num_comments) > 10)

  ## Expressions example

      # Augment a previous group_by with a having condition.
      Post |> or_having([p], avg(p.num_comments) > 10)

  """
  defmacro or_having(query, binding \\ [], expr) do
    Builder.Filter.build(:having, :or, query, binding, expr, __CALLER__)
  end

  @doc """
  Preloads the associations into the result set.

  Imagine you have an schema `Post` with a `has_many :comments`
  association and you execute the following query:

      Repo.all from p in Post, preload: [:comments]

  The example above will fetch all posts from the database and then do
  a separate query returning all comments associated with the given posts.
  The comments are then processed and associated to each returned `post`
  under the `comments` field.

  Often times, you may want posts and comments to be selected and
  filtered in the same query. For such cases, you can explicitly tell
  an existing join to be preloaded into the result set:

      Repo.all from p in Post,
                 join: c in assoc(p, :comments),
                 where: c.published_at > p.updated_at,
                 preload: [comments: c]

  In the example above, instead of issuing a separate query to fetch
  comments, Ecto will fetch posts and comments in a single query and
  then do a separate pass associating each comment to its parent post.
  Therefore, instead of returning `number_of_posts * number_of_comments`
  results, like a `join` would, it returns only posts with the `comments`
  fields properly filled in.

  Nested associations can also be preloaded in both formats:

      Repo.all from p in Post,
                 preload: [comments: :likes]

      Repo.all from p in Post,
                 join: c in assoc(p, :comments),
                 join: l in assoc(c, :likes),
                 where: l.inserted_at > c.updated_at,
                 preload: [comments: {c, likes: l}]

  ## Preload queries

  Preload also allows queries to be given, allowing you to filter or
  customize how the preloads are fetched:

      comments_query = from c in Comment, order_by: c.published_at
      Repo.all from p in Post, preload: [comments: ^comments_query]

  The example above will issue two queries, one for loading posts and
  then another for loading the comments associated with the posts.
  Comments will be ordered by `published_at`.

  Note: keep in mind operations like limit and offset in the preload
  query will affect the whole result set and not each association. For
  example, the query below:

      comments_query = from c in Comment, order_by: c.popularity, limit: 5
      Repo.all from p in Post, preload: [comments: ^comments_query]

  won't bring the top of comments per post. Rather, it will only bring
  the 5 top comments across all posts.

  ## Preload functions

  Preload also allows functions to be given. In such cases, the function
  receives the IDs of the parent association and it must return the associated
  data. Ecto then will map this data and sort it by the relationship key:

      comment_preloader = fn post_ids -> fetch_comments_by_post_ids(post_ids) end
      Repo.all from p in Post, preload: [comments: ^comment_preloader]

  This is useful when the whole dataset was already loaded or must be
  explicitly fetched from elsewhere. The IDs received by the preloading
  function and the result returned depends on the association type:

    * For `has_many` and `belongs_to` - the function receives the IDs of
      the parent association and it must return a list of maps or structs
      with the associated entries. The associated map/struct must contain
      the "foreign_key" field. For example, if a post has many comments,
      when preloading the comments with a custom function, the function
      will receive a list of "post_ids" as argument and it must return
      maps or structs representing the comments. The maps/structs must
      include the `:post_id` field

    * For `has_many :through` - it behaves similarly to a regular `has_many`
      but note that the IDs received are the ones from the closest
      parent and not the furthest one. Imagine for example a post has
      many comments and each comment has an author. Therefore, a post
      may have many comments_authors, written as
      `has_many :comments_authors, through: [:comments, :author]`. When
      preloading authors with a custom function via `:comments_authors`,
      the function will receive the IDs of the comments and not of the
      posts. That's because through associations are still loaded step
      by step

    * For `many_to_many` -  the function receives the IDs of the parent
      association and it must return a tuple with the parent id as first
      element and the association map or struct as second. For example,
      if a post has many tags, when preloading the tags with a custom
      function, the function will receive a list of "post_ids" as argument
      and it must return a tuple in the format of `{post_id, tag}`

  ## Keywords example

      # Returns all posts, their associated comments, and the associated
      # likes for those comments.
      from(p in Post,
        preload: [:comments, comments: :likes],
        select: p)

  ## Expressions examples

      Post |> preload(:comments) |> select([p], p)

      Post
      |> join(:left, [p], c in assoc(p, :comments))
      |> preload([p, c], [:user, comments: c])
      |> select([p], p)

  """
  defmacro preload(query, bindings \\ [], expr) do
    Builder.Preload.build(query, bindings, expr, __CALLER__)
  end

  @doc """
  Restricts the query to return the first result ordered by primary key.

  The query will be automatically ordered by the primary key
  unless `order_by` is given or `order_by` is set in the query.
  Limit is always set to 1.

  ## Examples

      Post |> first |> Repo.one
      query |> first(:inserted_at) |> Repo.one
  """
  def first(queryable, order_by \\ nil)

  def first(%Ecto.Query{} = query, nil) do
    query = %{query | limit: limit()}
    case query do
      %{order_bys: []} ->
        %{query | order_bys: [order_by_pk(query, :asc)]}
      %{} ->
        query
    end
  end
  def first(queryable, nil), do: first(Ecto.Queryable.to_query(queryable), nil)
  def first(queryable, key), do: first(order_by(queryable, ^key), nil)

  @doc """
  Restricts the query to return the last result ordered by primary key.

  The query ordering will be automatically reversed, with ASC
  columns becoming DESC columns (and vice-versa) and limit is set
  to 1. If there is no ordering, the query will be automatically
  ordered decreasingly by primary key.

  ## Examples

      Post |> last |> Repo.one
      query |> last(:inserted_at) |> Repo.one
  """
  def last(queryable, order_by \\ nil)
  def last(queryable, nil), do: %{reverse_order(queryable) | limit: limit()}
  def last(queryable, key), do: last(order_by(queryable, ^key), nil)

  defp limit do
    %QueryExpr{expr: 1, params: [], file: __ENV__.file, line: __ENV__.line}
  end

  defp field(ix, field) when is_integer(ix) and is_atom(field) do
    {{:., [], [{:&, [], [ix]}, field]}, [], []}
  end

  defp order_by_pk(query, dir) do
    schema = assert_schema!(query)
    pks    = schema.__schema__(:primary_key)
    expr   = for pk <- pks, do: {dir, field(0, pk)}
    %QueryExpr{expr: expr, file: __ENV__.file, line: __ENV__.line}
  end

  defp assert_schema!(%{from: %Ecto.Query.FromExpr{source: {_source, schema}}}) when schema != nil, do: schema
  defp assert_schema!(query) do
    raise Ecto.QueryError, query: query, message: "expected a from expression with a schema"
  end

  @doc """
  Returns `true` if query has binding with a given name, otherwise `false`.

  For more information on named bindings see "Named bindings" in this module doc.
  """
  def has_named_binding?(%Ecto.Query{aliases: aliases}, key) do
    Map.has_key?(aliases, key)
  end

  def has_named_binding?(queryable, _key)
      when is_atom(queryable) or is_binary(queryable) or is_tuple(queryable) do
    false
  end

  def has_named_binding?(queryable, key) do
    has_named_binding?(Ecto.Queryable.to_query(queryable), key)
  end

  @doc """
  Reverses the ordering of the query.

  ASC columns become DESC columns (and vice-versa). If the query
  has no order_bys, it orders by the inverse of the primary key.

  ## Examples

      query |> reverse_order |> Repo.one
      Post |> order(asc: :id) |> reverse_order == Post |> order(desc: :id)
  """
  def reverse_order(%Ecto.Query{} = query) do
    update_in(query.order_bys, fn
      [] -> [order_by_pk(query, :desc)]
      order_bys -> Enum.map(order_bys, &reverse_order_by/1)
    end)
  end

  def reverse_order(queryable) do
    reverse_order(Ecto.Queryable.to_query(queryable))
  end

  defp reverse_order_by(%{expr: expr} = order_by) do
    %{
      order_by
      | expr:
          Enum.map(expr, fn
            {:desc, ast} -> {:asc, ast}
            {:desc_nulls_last, ast} -> {:asc_nulls_first, ast}
            {:desc_nulls_first, ast} -> {:asc_nulls_last, ast}
            {:asc, ast} -> {:desc, ast}
            {:asc_nulls_last, ast} -> {:desc_nulls_first, ast}
            {:asc_nulls_first, ast} -> {:desc_nulls_last, ast}
          end)
    }
  end
end
