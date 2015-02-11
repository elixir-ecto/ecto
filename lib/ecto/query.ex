defmodule Ecto.Query do
  @moduledoc ~S"""
  Provides the Query DSL.

  Queries are used to retrieve and manipulate data in a repository
  (see `Ecto.Repo`). Although this module provides a complete API,
  supporting expressions like `where/3`, `select/3` and so forth,
  most of the times developers need to import only the `from/2`
  macro.

      # Imports only from/1 and from/2 from Ecto.Query
      import Ecto.Query, only: [from: 2]

      # Create a query
      query = from w in Weather,
            where: w.prcp > 0,
           select: w.city

      # Send the query to the repository
      Repo.all(query)

  ## Composition

  Ecto queries are composable. For example, the query above can
  actually be defined in two parts:

      # Create a query
      query = from w in Weather, where: w.prcp > 0

      # Extend the query
      query = from w in query, select: w.city

  Keep in mind though the variable names used on the left-hand
  side of `in` are just a convenience, they are not taken into
  account in the query generation.

  Any value can be used on the right-side of `in` as long as it
  implements the `Ecto.Queryable` protocol.

  ## Query expressions

  Ecto allows a limitted set of expressions to be used inside queries:

    * Comparison operators: `==`, `!=`, `<=`, `>=`, `<`, `>`
    * Boolean operators: `and`, `or`, `not`
    * Inclusion operator: `in/2`
    * Search functions: `like/2` and `ilike/2`
    * Null check functions: `is_nil/1`
    * Aggregates: `count/1`, `avg/1`, `sum/1`, `min/1`, `max/1`

  Futhermore, Ecto allows the following literals inside queries:

    * Integers: `1`, `2`, `3`
    * Floats: `1.0`, `2.0`, `3.0`
    * Booleans: `true`, `false`
    * Binaries: `<<1, 2, 3>>`
    * Strings: `"foo bar"`, `~s(this is a string)`
    * Arrays: `[1, 2, 3]`, `~w(interpolate words)`
    * UUIDs: `uuid("0123456789abcdef")`

  External values and Elixir expressions can be injected into a query
  expression with `^`:

      def with_minimum(age, height_ft) do
          from u in User,
        where: u.age > ^age and u.height > ^(height_ft * 3.28)
      end

      with_minimum(18, 5.0)

  Finally, Ecto provides two conveniences for dynamically generating
  queries. The first is the `field/2` function which allows developers
  to dynamically choose a field to query:

      def at_least_four(doors_or_tires) do
          from c in Car,
        where: field(u, ^doors_or_tires) >= 4
      end

  In the example above, both `at_least_four(:doors)` and `at_least_four(:tires)`
  would be valid calls as the field is dynamically inserted.

  The other convenience is called fragments which allows developers to send
  any expression to the database via the `fragment(...)` function:

      def unpublished_by_title(title)
        from p in Post,
          where: is_nil(p.published_at) and
                 fragment("downcase(?) == ?", p.title, ^title)
      end

  Fragments are sent directly to the database while also allowing field names
  like `p.title` and values like `^title` to be interpolated.

  ## Casting

  Ecto is able to cast interpolated values in queries:

      age = "1"
      Repo.all(from u in User, where: u.age > ^age)

  The example above works because `u.age` is tagged as an :integer
  in the User model and therefore Ecto will attempt to cast the
  interpolated `^age` to integer. In case a value cannot be cast,
  `Ecto.CastError` is raised.

  In some situations, Ecto is unable to infer the type for interpolated
  values (as a database would be unable) and you may need to explicitly
  tag it with the type/2 function:

      type(^"1", :integer)
      type(^<<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>, :uuid)

  It is important to keep in mind that Ecto cannot cast nil values in
  queries. Passing nil automatically causes the query to fail.

  ## Query expansion

  In all examples so far, we have used the **keywords query syntax** to create
  a query. Our first example:

      import Ecto.Query

         from w in Weather,
       where: w.prcp > 0,
      select: w.city

  Simply expands to the following **query expressions**:

      from(w in Weather) |> where([w], w.prcp > 0) |> select([w], w.city)

  Which then expands to:

      select(where(from(w in Weather), [w], w.prcp > 0), [w], w.city)

  This module documents each of those macros, providing examples both
  in the keywords query and in the query expression formats.
  """

  defstruct [sources: nil, from: nil, joins: [], wheres: [], select: nil,
             order_bys: [], limit: nil, offset: nil, group_bys: [],
             havings: [], preloads: [], assocs: [], distincts: [], lock: nil]
  @opaque t :: %__MODULE__{}

  defmodule QueryExpr do
    @moduledoc false
    defstruct [expr: nil, params: [], file: nil, line: nil]
  end

  defmodule SelectExpr do
    @moduledoc false
    defstruct [expr: nil, params: [], file: nil, line: nil, fields: []]
  end

  defmodule JoinExpr do
    @moduledoc false
    defstruct [:qual, :source, :on, :file, :line, :assoc, :ix]
  end

  defmodule Tagged do
    @moduledoc false
    # * value is the tagged value
    # * tag is the directly tagged value, like Ecto.DateTime
    # * type is the underlying tag type, like :datetime
    defstruct [:value, :tag, :type]
  end

  alias Ecto.Query.Builder
  alias Ecto.Query.Builder.From
  alias Ecto.Query.Builder.Where
  alias Ecto.Query.Builder.Select
  alias Ecto.Query.Builder.Distinct
  alias Ecto.Query.Builder.OrderBy
  alias Ecto.Query.Builder.LimitOffset
  alias Ecto.Query.Builder.GroupBy
  alias Ecto.Query.Builder.Having
  alias Ecto.Query.Builder.Preload
  alias Ecto.Query.Builder.Join
  alias Ecto.Query.Builder.Lock

  @doc """
  Resets a previously set field on a query.

  It can reset any query field except the query source (`from`).

  ## Example

      query |> Ecto.Query.exclude(:select)

  """
  def exclude(%Ecto.Query{} = query, field), do: do_exclude(query, field)
  def exclude(query, field), do: do_exclude(Ecto.Queryable.to_query(query), field)

  defp do_exclude(%Ecto.Query{} = query, :join), do: %{query | joins: []}
  defp do_exclude(%Ecto.Query{} = query, :where), do: %{query | wheres: []}
  defp do_exclude(%Ecto.Query{} = query, :order_by), do: %{query | order_bys: []}
  defp do_exclude(%Ecto.Query{} = query, :group_by), do: %{query | group_bys: []}
  defp do_exclude(%Ecto.Query{} = query, :having), do: %{query | havings: []}
  defp do_exclude(%Ecto.Query{} = query, :distinct), do: %{query | distincts: []}
  defp do_exclude(%Ecto.Query{} = query, :select), do: %{query | select: nil}
  defp do_exclude(%Ecto.Query{} = query, :limit), do: %{query | limit: nil}
  defp do_exclude(%Ecto.Query{} = query, :offset), do: %{query | offset: nil}
  defp do_exclude(%Ecto.Query{} = query, :lock), do: %{query | lock: nil}
  defp do_exclude(%Ecto.Query{} = query, :preload), do: %{query | preloads: [], assocs: []}

  @doc """
  Creates a query.

  It can either be a keyword query or a query expression. If it is a
  keyword query the first argument should be an `in` expression and
  the second argument a keyword query where they keys are expression
  types and the values are expressions.

  If it is a query expression the first argument is the original query
  and the second argument the expression.

  ## Keywords examples

      from(City, select: c)

  ## Expressions examples

      City |> select([c], c)

  ## Examples

      def paginate(query, page, size) do
        from query,
          limit: size,
          offset: (page-1) * size
      end

  The example above does not use `in` because none of `limit` and `offset`
  requires such. However, extending a query with where expression would
  require so:

      def published(query) do
        from p in query, where: p.published_at != nil
      end

  Notice we have created a `p` variable to represent each item in the query.
  In case the given query has more than one `from` expression, each of them
  must be given in the order they were bound:

      def published_multi(query) do
        from [p,o] in query,
        where: p.published_at != nil and o.published_at != nil
      end

  Note the variables `p` and `q` must be named as you find more convenient
  as they have no importance in the query sent to the database.
  """
  defmacro from(expr, kw \\ []) do
    unless Keyword.keyword?(kw) do
      raise ArgumentError, "second argument to `from` must be a keyword list"
    end

    {quoted, binds, count_bind} = From.build(expr, __CALLER__)
    from(kw, __CALLER__, count_bind, quoted, binds)
  end

  @binds    [:where, :select, :distinct, :order_by, :group_by, :having, :limit, :offset, :preload]
  @no_binds [:lock]
  @joins    [:join, :inner_join, :left_join, :right_join, :full_join]

  defp from([{type, expr}|t], env, count_bind, quoted, binds) when type in @binds do
    # If all bindings are integer indexes keep AST Macro.expand'able to %Query{},
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
    qual =
      case join do
        :join       -> :inner
        :inner_join -> :inner
        :left_join  -> :left
        :right_join -> :right
        :full_join  -> :full
      end

    {t, on} = collect_on(t, nil)
    {quoted, binds, count_bind} = Join.build(quoted, qual, binds, expr, on, count_bind, env)
    from(t, env, count_bind, quoted, binds)
  end

  defp from([{:on, _value}|_], _env, _count_bind, _quoted, _binds) do
    Builder.error! "`on` keyword must immediately follow a join"
  end

  defp from([{key, _value}|_], _env, _count_bind, _quoted, _binds) do
    Builder.error! "unsupported #{inspect key} in keyword query expression"
  end

  defp from([], _env, _count_bind, quoted, _binds) do
    quoted
  end

  defp collect_on([{:on, expr}|t], nil),
    do: collect_on(t, expr)
  defp collect_on([{:on, expr}|t], acc),
    do: collect_on(t, {:and, [], [acc, expr]})
  defp collect_on(other, acc),
    do: {other, acc}

  @doc """
  A join query expression.

  Receives a model that is to be joined to the query and a condition to
  do the joining on. The join condition can be any expression that evaluates
  to a boolean value. The join is by default an inner join, the qualifier
  can be changed by giving the atoms: `:inner`, `:left`, `:right` or
  `:full`. For a keyword query the `:join` keyword can be changed to:
  `:inner_join`, `:left_join`, `:right_join` or `:full_join`.

  The join condition can be automatically set when doing an association
  join. An association join can be done on any association field
  (`has_many`, `has_one`, `belongs_to`).

  ## Keywords examples

         from c in Comment,
        join: p in Post, on: c.post_id == p.id,
      select: {p.title, c.text}

         from p in Post,
        left_join: c in assoc(p, :comments),
      select: {p, c}

  ## Expressions examples

      Comment
      |> join(:inner, [c], p in Post, c.post_id == p.id)
      |> select([c, p], {p.title, c.text})

      Post
      |> join(:left, [p], c in assoc(p, :comments))
      |> select([p, c], {p, c})
  """
  defmacro join(query, qual, binding, expr, on \\ nil) do
    Join.build(query, qual, binding, expr, on, nil, __CALLER__)
    |> elem(0)
  end

  @doc """
  A select query expression.

  Selects which fields will be selected from the model and any transformations
  that should be performed on the fields. Any expression that is accepted in a
  query can be a select field.

  There can only be one select expression in a query, if the select expression
  is omitted, the query will by default select the full model.

  The sub-expressions in the query can be wrapped in lists or tuples as shown in
  the examples. A full model can also be selected.

  ## Keywords examples

      from(c in City, select: c) # selects the entire model
      from(c in City, select: {c.name, c.population})
      from(c in City, select: [c.name, c.county])
      from(c in City, select: {c.name, ^to_binary(40 + 2), 43})

  ## Expressions examples

      City |> select([c], c)
      City |> select([c], {c.name, c.country})

  """
  defmacro select(query, binding, expr) do
    Select.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A distinct query expression.

  Only keep one row for each combination of values in the `distinct` query
  expression.

  The row that is being kept depends on the ordering of the rows. To ensure
  results are consistent, if an `order_by` expression is also added to the
  query, its leftmost part must first reference all the fields in the
  `distinct` expression before referencing another field.

  ## Keywords examples

      # Returns the list of different categories in the Post model
      from(p in Post, distinct: p.category)

      # Returns the first (by date) for each different categories of Post
      from(p in Post,
         distinct: p.category,
         order_by: [p.category, p.date])

  ## Expressions examples

      Post
      |> distinct([p], p.category)
      |> order_by([p], [p.category, p.author])

  """
  defmacro distinct(query, binding, expr) do
    Distinct.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A where query expression.

  `where` expressions are used to filter the result set. If there is more
  than one where expression, they are combined with `and` operator. All
  where expression have to evaluate to a boolean value.

  ## Keywords examples

      from(c in City, where: c.state == "Sweden")

  ## Expressions examples

      City |> where([c], c.state == "Sweden")

  """
  defmacro where(query, binding, expr) do
    Where.build(query, binding, expr, __CALLER__)
  end

  @doc """
  An order by query expression.

  Orders the fields based on one or more fields. It accepts a single field
  or a list field, the direction can be specified in a keyword list as shown
  in the examples. There can be several order by expressions in a query.

  ## Keywords examples

      from(c in City, order_by: c.name, order_by: c.population)
      from(c in City, order_by: [c.name, c.population])
      from(c in City, order_by: [asc: c.name, desc: c.population])

  ## Expressions examples

      City |> order_by([c], asc: c.name, desc: c.population)

  ## Atom values

  For simplicity, `order_by` also allows the fields to be given
  as atoms. In such cases, the field always applies to the source
  given in `from` (i.e. the first binding). For example, the two
  expressions below are equivalent:

      from(c in City, order_by: [asc: :name, desc: :population])
      from(c in City, order_by: [asc: c.name, desc: c.population])

  A keyword list can also be interpolated:

      values = [asc: :name, desc: :population]
      from(c in City, order_by: ^values)

  """
  defmacro order_by(query, binding, expr)  do
    OrderBy.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A limit query expression.

  Limits the number of rows selected from the result. Can be any expression but
  have to evaluate to an integer value and it can't include any field.

  If `limit` is given twice, it overrides the previous value.

  ## Keywords examples

      from(u in User, where: u.id == current_user, limit: 1)

  ## Expressions examples

      User |> where([u], u.id == current_user) |> limit([u], 1)

  """
  defmacro limit(query, binding, expr) do
    LimitOffset.build(:limit, query, binding, expr, __CALLER__)
  end

  @doc """
  An offset query expression.

  Offsets the number of rows selected from the result. Can be any expression
  but have to evaluate to an integer value and it can't include any field.

  If `offset` is given twice, it overrides the previous value.

  ## Keywords examples

      # Get all posts on page 4
      from(p in Post, limit: 10, offset: 30)

  ## Expressions examples

      Post |> limit([p], 10) |> offset([p], 30)

  """
  defmacro offset(query, binding, expr) do
    LimitOffset.build(:offset, query, binding, expr, __CALLER__)
  end

  @doc """
  A lock query expression.

  Provides support for row-level pessimistic locking using
  SELECT ... FOR UPDATE or other, database-specific, locking clauses.
  Can be any expression but have to evaluate to a boolean value or a
  string and it can't include any field.

  If `lock` is given twice, it overrides the previous value.

  ## Keywords examples

      from(u in User, where: u.id == current_user, lock: true)
      from(u in User, where: u.id == current_user, lock: \"FOR SHARE NOWAIT\")

  ## Expressions examples

      User |> where(u.id == current_user) |> lock(true)
      User |> where(u.id == current_user) |> lock(\"FOR SHARE NOWAIT\")

  """
  defmacro lock(query, expr) do
    Lock.build(query, expr, __CALLER__)
  end

  @doc """
  A group by query expression.

  Groups together rows from the model that have the same values in the given
  fields. Using `group_by` "groups" the query giving it different semantics
  in the `select` expression. If a query is grouped only fields that were
  referenced in the `group_by` can be used in the `select` or if the field
  is given as an argument to an aggregate function.

  ## Keywords examples

      # Returns the number of posts in each category
      from(p in Post,
        group_by: p.category,
        select: {p.category, count(p.id)})

      # Group on all fields on the Post model
      from(p in Post,
        group_by: p,
        select: p)

  ## Expressions examples

      Post |> group_by([p], p.category) |> select([p], count(p.id))

  """
  defmacro group_by(query, binding, expr) do
    GroupBy.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A having query expression.

  Like `where` `having` filters rows from the model, but after the grouping is
  performed giving it the same semantics as `select` for a grouped query
  (see `group_by/3`). `having` groups the query even if the query has no
  `group_by` expression.

  ## Keywords examples

      # Returns the number of posts in each category where the
      # average number of comments is above ten
      from(p in Post,
        group_by: p.category,
        having: avg(p.num_comments) > 10,
        select: {p.category, count(p.id)})

  ## Expressions examples

      Post
      |> group_by([p], p.category)
      |> having([p], avg(p.num_comments) > 10)
      |> select([p], count(p.id))
  """
  defmacro having(query, binding, expr) do
    Having.build(query, binding, expr, __CALLER__)
  end

  @doc """
  Pre-loads the associations into the given model.

  Pre-loading allow developers to specify associations that are pre-loaded
  into the model. Consider this example:

      Repo.all from p in Post, preload: [:comments]

  The example above will fetch all posts from the database and then do
  a separate query returning all comments associated to the given posts.

  However, often times, you want posts and comments to be selected and
  filtered in the same query. For such cases, you can explicitly tell
  the association to be pre-loaded into the model:

      Repo.all from p in Post,
                 join: c in assoc(p, :comments),
                 where: c.published_at > p.updated_at,
                 preload: [comments: c]

  In the example above, instead of issuing a separate query to fetch
  comments, Ecto will fetch posts and comments in a single query.

  Nested associations can also be preloaded in both formats:

      Repo.all from p in Post,
                 preload: [comments: :likes]

      Repo.all from p in Post,
                 join: c in assoc(p, :comments),
                 join: l in assoc(c, :likes),
                 where: l.inserted_at > c.updated_at,
                 preload: [comments: {c, likes: l}]

  Keep in mind though both formats cannot be nested arbitrary. For
  example, the query below is invalid because we cannot preload
  likes with the join association `c`.

      Repo.all from p in Post,
                 join: c in assoc(p, :comments),
                 preload: [comments: {c, :likes}]

  ## Keywords examples

      # Returns all posts and their associated comments
      from(p in Post,
        preload: [:comments, comments: :likes],
        select: p)

  ## Expressions examples

      Post |> preload(:comments) |> select([p], p)
      Post |> preload([p, c], [:user, comments: c]) |> select([p], p)

  """
  defmacro preload(query, bindings \\ [], expr) do
    Preload.build(query, bindings, expr, __CALLER__)
  end
end
