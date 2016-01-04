defmodule Ecto.Query do
  @moduledoc ~S"""
  Provides the Query DSL.

  Queries are used to retrieve and manipulate data in a repository
  (see `Ecto.Repo`). Although this module provides a complete API,
  supporting expressions like `where/3`, `select/3` and so forth,
  most of the time developers need to import only the `from/2`
  macro.

      # Imports only from/2 of Ecto.Query
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

  Ecto allows a limited set of expressions inside queries. In the
  query below, for example, we use `w.prcp` to access a field, the
  `>` comparison operator and the literal `0`:

      query = from w in Weather, where: w.prcp > 0

  You can find the full list of operations in `Ecto.Query.API`.
  Besides the operations listed here, the following literals are
  supported in queries:

    * Integers: `1`, `2`, `3`
    * Floats: `1.0`, `2.0`, `3.0`
    * Booleans: `true`, `false`
    * Binaries: `<<1, 2, 3>>`
    * Strings: `"foo bar"`, `~s(this is a string)`
    * Arrays: `[1, 2, 3]`, `~w(interpolate words)`

  All other types must be passed as a parameter using interpolation
  as explained below.

  ## Interpolation

  External values and Elixir expressions can be injected into a query
  expression with `^`:

      def with_minimum(age, height_ft) do
          from u in User,
        where: u.age > ^age and u.height > ^(height_ft * 3.28)
      end

      with_minimum(18, 5.0)

  Interpolation can also be used with the `field/2` function which allows
  developers to dynamically choose a field to query:

      def at_least_four(doors_or_tires) do
          from c in Car,
        where: field(c, ^doors_or_tires) >= 4
      end

  In the example above, both `at_least_four(:doors)` and `at_least_four(:tires)`
  would be valid calls as the field is dynamically inserted.

  ## Casting

  Ecto is able to cast interpolated values in queries:

      age = "1"
      Repo.all(from u in User, where: u.age > ^age)

  The example above works because `u.age` is tagged as an :integer
  in the User schema and therefore Ecto will attempt to cast the
  interpolated `^age` to integer. When a value cannot be cast,
  `Ecto.CastError` is raised.

  In some situations, Ecto is unable to infer the type for interpolated
  values (as a database would be unable) and you may need to explicitly
  tag it with the type/2 function:

      type(^"1", :integer)
      type(^<<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>, Ecto.UUID)

  It is important to keep in mind that Ecto cannot cast nil values in
  queries. Passing nil automatically causes the query to fail.

  ## Query Prefix

  It is possible to set a prefix for the table name in queries.  For Postgres users,
  this will specify the schema where the table is located, while for MySQL users this will
  specify the database where the table is located.  When no prefix is set, Postgres queries
  are assumed to be in the public schema, while MySQL queries are assumed to be in the
  database set in the config for the repo.

  Set the prefix on a query:

      query = from u in User, select: u
      queryable = %{query | prefix: "foo"}
      results = Repo.all(queryable)

  Set the prefix without the query syntax:

      results =
        User
        |> Ecto.Queryable.to_query
        |> Map.put(:prefix, "foo")
        |> Repo.all

  When a prefix is set in a query, all loaded structs will belong to that
  prefix, so operations like update and delete will be applied to the
  proper prefix. In case you want to manually set the prefix for new data,
  specially on insert, use `Ecto.put_meta/2`.

  ## Macro API

  In all examples so far we have used the **keywords query syntax** to
  create a query:

      import Ecto.Query
      from w in Weather, where: w.prcp > 0, select: w.city

  Behind the scenes, the query above expands to the set of macros defined
  in this module:

      from(w in Weather) |> where([w], w.prcp > 0) |> select([w], w.city)

  which then expands to:

      select(where(from(w in Weather), [w], w.prcp > 0), [w], w.city)

  This module documents each of those macros, providing examples in both
  the keywords query and query expression formats.
  """

  defstruct [prefix: nil, sources: nil, from: nil, joins: [], wheres: [], select: nil,
             order_bys: [], limit: nil, offset: nil, group_bys: [], updates: [],
             havings: [], preloads: [], assocs: [], distinct: nil, lock: nil]
  @opaque t :: %__MODULE__{}

  defmodule QueryExpr do
    @moduledoc false
    defstruct [:expr, :file, :line, params: %{}]
  end

  defmodule SelectExpr do
    @moduledoc false
    defstruct [:expr, :file, :line, fields: [], params: %{}, take: %{}]
  end

  defmodule JoinExpr do
    @moduledoc false
    defstruct [:qual, :source, :on, :file, :line, :assoc, :ix, params: %{}]
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
  alias Ecto.Query.Builder.Filter
  alias Ecto.Query.Builder.Select
  alias Ecto.Query.Builder.Distinct
  alias Ecto.Query.Builder.OrderBy
  alias Ecto.Query.Builder.LimitOffset
  alias Ecto.Query.Builder.GroupBy
  alias Ecto.Query.Builder.Preload
  alias Ecto.Query.Builder.Join
  alias Ecto.Query.Builder.Lock
  alias Ecto.Query.Builder.Update

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
  defp do_exclude(%Ecto.Query{} = query, :distinct), do: %{query | distinct: nil}
  defp do_exclude(%Ecto.Query{} = query, :select), do: %{query | select: nil}
  defp do_exclude(%Ecto.Query{} = query, :limit), do: %{query | limit: nil}
  defp do_exclude(%Ecto.Query{} = query, :offset), do: %{query | offset: nil}
  defp do_exclude(%Ecto.Query{} = query, :lock), do: %{query | lock: nil}
  defp do_exclude(%Ecto.Query{} = query, :preload), do: %{query | preloads: [], assocs: []}

  @doc """
  Creates a query.

  It can either be a keyword query or a query expression. If it is a
  keyword query the first argument should be an `in` expression and
  the second argument a keyword query where the keys are expression
  types and the values are expressions.

  If it is a query expression the first argument is the original query
  and the second argument the expression.

  ## Keywords example

      from(City, select: c)

  ## Expressions example

      City |> select([c], c)

  ## Examples

      def paginate(query, page, size) do
        from query,
          limit: ^size,
          offset: ^((page-1) * size)
      end

  The example above does not use `in` because `limit` and `offset`
  do not require such. However, extending a query with a where expression would
  require the use of `in`:

      def published(query) do
        from p in query, where: not(is_nil(p.published_a))
      end

  Notice we have created a `p` variable to represent each item in the query.
  When the given query has more than one `from` expression, a variable
  must be given for each in the order they were bound:

      def published_multi(query) do
        from [p,o] in query,
        where: not(is_nil(p.published_at)) and not(is_nil(o.published_at))
      end

  Note the variables `p` and `o` can be named whatever you like
  as they have no importance in the query sent to the database.
  """
  defmacro from(expr, kw \\ []) do
    unless Keyword.keyword?(kw) do
      raise ArgumentError, "second argument to `from` must be a keyword list"
    end

    {quoted, binds, count_bind} = From.build(expr, __CALLER__)
    from(kw, __CALLER__, count_bind, quoted, binds)
  end

  @binds    [:where, :select, :distinct, :order_by, :group_by,
             :having, :limit, :offset, :preload, :update]
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

  Receives a source that is to be joined to the query and a condition for
  the join. The join condition can be any expression that evaluates
  to a boolean value. The join is by default an inner join, the qualifier
  can be changed by giving the atoms: `:inner`, `:left`, `:right` or
  `:full`. For a keyword query the `:join` keyword can be changed to:
  `:inner_join`, `:left_join`, `:right_join` or `:full_join`.

  Currently it is possible to join on an Ecto.Schema (a module), an
  existing source (a binary representing a table), an association or a
  fragment. See the examples below.

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

  ## Joining with fragments

  When you need to join on a complex expression that cannot be
  expressed via Ecto associations, Ecto supports fragments in joins:

      Comment
      |> join(:inner, [c], p in fragment("SOME COMPLEX QUERY", c.id, ^some_param))

  This style discouraged due to its complexity.
  """
  defmacro join(query, qual, binding \\ [], expr, on \\ nil) do
    Join.build(query, qual, binding, expr, on, nil, __CALLER__)
    |> elem(0)
  end

  @doc """
  A select query expression.

  Selects which fields will be selected from the schema and any transformations
  that should be performed on the fields. Any expression that is accepted in a
  query can be a select field.

  The sub-expressions in the query can be wrapped in lists, tuples or maps as
  shown in the examples. A full schema can also be selected.

  There can only be one select expression in a query, if the select expression
  is omitted, the query will by default select the full schema.

  ## Keywords examples

      from(c in City, select: c) # selects the entire schema
      from(c in City, select: {c.name, c.population})
      from(c in City, select: [c.name, c.county])
      from(c in City, select: {c.name, ^to_string(40 + 2), 43})
      from(c in City, select: %{n: c.name, answer: 42})

  ## Expressions examples

      City |> select([c], c)
      City |> select([c], {c.name, c.country})
      City |> select([c], %{"name" => c.name})

  """
  defmacro select(query, binding \\ [], expr) do
    Select.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A distinct query expression.

  When true, only keeps distinct values from the resulting
  select expression.

  If supported by your database, you can also pass query
  expressions to distinct and it will generate a query
  with DISTINCT ON. In such cases, the row that is being
  kept depends on the ordering of the rows. When an `order_by`
  expression is also added to the query, all fields in the
  `distinct` expression are automatically referenced `order_by`
  too.

  `distinct` also accepts a list of atoms where each atom refers to
  a field in source.

  ## Keywords examples

      # Returns the list of different categories in the Post schema
      from(p in Post, distinct: true, select: p.category)

      # If your database supports DISTINCT ON(),
      # you can pass expressions to distinct too
      from(p in Post,
         distinct: p.category,
         order_by: [p.date])

      # Using atoms
      from(p in Post, distinct: :category, order_by: :date)

  ## Expressions example

      Post
      |> distinct(true)
      |> order_by([p], [p.category, p.author])

  """
  defmacro distinct(query, binding \\ [], expr) do
    Distinct.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A where query expression.

  `where` expressions are used to filter the result set. If there is more
  than one where expression, they are combined with an `and` operator. All
  where expressions have to evaluate to a boolean value.

  `where` also accepts a keyword list where the field given as key is going to
  be compared with the given value. The fields will always refer to the source
  given in `from`.

  ## Keywords example

      from(c in City, where: c.state == "Sweden")
      from(c in City, where: [state: "Sweden"])

  It is also possible to interpolate the whole keyword list, allowing you to
  dynamically filter the source:

      filters = [state: "Sweden"]
      from(c in City, where: ^filters)

  ## Expressions example

      City |> where([c], c.state == "Sweden")
      City |> where(state: "Sweden")

  """
  defmacro where(query, binding \\ [], expr) do
    Filter.build(:where, query, binding, expr, __CALLER__)
  end

  @doc """
  An order by query expression.

  Orders the fields based on one or more fields. It accepts a single field
  or a list of fields. The direction can be specified in a keyword list as shown
  in the examples. There can be several order by expressions in a query.

  `order_by` also accepts a list of atoms where each atom refers to a field in
  source or a keyword list where the direction is given as key and the field
  to order as value.

  ## Keywords examples

      from(c in City, order_by: c.name, order_by: c.population)
      from(c in City, order_by: [c.name, c.population])
      from(c in City, order_by: [asc: c.name, desc: c.population])

      from(c in City, order_by: [:name, :population])
      from(c in City, order_by: [asc: :name, desc: :population])

  A keyword list can also be interpolated:

      values = [asc: :name, desc: :population]
      from(c in City, order_by: ^values)

  ## Expressions example

      City |> order_by([c], asc: c.name, desc: c.population)
      City |> order_by(asc: :name) # Sorts by the cities name

  """
  defmacro order_by(query, binding \\ [], expr)  do
    OrderBy.build(query, binding, expr, __CALLER__)
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
    LimitOffset.build(:limit, query, binding, expr, __CALLER__)
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
    LimitOffset.build(:offset, query, binding, expr, __CALLER__)
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
    Lock.build(query, expr, __CALLER__)
  end

  @doc ~S"""
  An update query expression.

  Updates are used to update the filtered entries. In order for
  updates to be applied, `Ecto.Repo.update_all/3` must be invoked.

  ## Keywords example

      from(u in User, update: [set: [name: "new name"]])

  ## Expressions example

      User |> update([u], set: [name: "new name"])
      User |> update(set: [name: "new name"])

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
    Update.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A group by query expression.

  Groups together rows from the schema that have the same values in the given
  fields. Using `group_by` "groups" the query giving it different semantics
  in the `select` expression. If a query is grouped, only fields that were
  referenced in the `group_by` can be used in the `select` or if the field
  is given as an argument to an aggregate function.

  `group_by` also accepts a list of atoms where each atom refers to
  a field in source.

  ## Keywords examples

      # Returns the number of posts in each category
      from(p in Post,
        group_by: p.category,
        select: {p.category, count(p.id)})

      # Group on all fields on the Post schema
      from(p in Post, group_by: p, select: p)

      # Using atoms
      from(p in Post, group_by: :category, select: {p.category, count(p.id)})

  ## Expressions example

      Post |> group_by([p], p.category) |> select([p], count(p.id))

  """
  defmacro group_by(query, binding \\ [], expr) do
    GroupBy.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A having query expression.

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
    Filter.build(:having, query, binding, expr, __CALLER__)
  end

  @doc """
  Preloads the associations into the given struct.

  Preloading allows developers to specify associations that are preloaded
  into the struct. Consider this example:

      Repo.all from p in Post, preload: [:comments]

  The example above will fetch all posts from the database and then do
  a separate query returning all comments associated to the given posts.

  However, often times, you want posts and comments to be selected and
  filtered in the same query. For such cases, you can explicitly tell
  the association to be preloaded into the struct:

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

  Keep in mind neither format can be nested arbitrarily. For
  example, the query below is invalid because we cannot preload
  likes with the join association `c`.

      Repo.all from p in Post,
                 join: c in assoc(p, :comments),
                 preload: [comments: {c, :likes}]

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

  ## Keywords example

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
