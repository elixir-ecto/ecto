defmodule Ecto.Query.API do
  @moduledoc """
  Lists all functions allowed in the query API.

    * Comparison operators: `==`, `!=`, `<=`, `>=`, `<`, `>`
    * Arithmetic operators: `+`, `-`, `*`, `/`
    * Boolean operators: `and`, `or`, `not`
    * Inclusion operator: `in/2`
    * Subquery operators: `any`, `all` and `exists`
    * Search functions: `like/2` and `ilike/2`
    * Null check functions: `is_nil/1`
    * Aggregates: `count/0`, `count/1`, `avg/1`, `sum/1`, `min/1`, `max/1`
    * Date/time intervals: `datetime_add/3`, `date_add/3`, `from_now/2`, `ago/2`
    * Inside select: `struct/2`, `map/2`, `merge/2`, `selected_as/2` and literals (map, tuples, lists, etc)
    * General: `fragment/1`, `field/2`, `type/2`, `as/1`, `parent_as/1`, `selected_as/1`

  Note the functions in this module exist for documentation
  purposes and one should never need to invoke them directly.
  Furthermore, it is possible to define your own macros and
  use them in Ecto queries (see docs for `fragment/1`).

  ## Intervals

  Ecto supports following values for `interval` option: `"year"`, `"month"`,
  `"week"`, `"day"`, `"hour"`, `"minute"`, `"second"`, `"millisecond"`, and
  `"microsecond"`.

  `Date`/`Time` functions like `datetime_add/3`, `date_add/3`, `from_now/2`,
  `ago/2` take `interval` as an argument.

  ## Window API

  Ecto also supports many of the windows functions found
  in SQL databases. See `Ecto.Query.WindowAPI` for more
  information.

  ## About the arithmetic operators

  The Ecto implementation of these operators provide only
  a thin layer above the adapters. So if your adapter allows you
  to use them in a certain way (like adding a date and an
  interval in PostgreSQL), it should work just fine in Ecto
  queries.
  """

  @dialyzer :no_return

  @doc """
  Binary `==` operation.
  """
  def left == right, do: doc! [left, right]

  @doc """
  Binary `!=` operation.
  """
  def left != right, do: doc! [left, right]

  @doc """
  Binary `<=` operation.
  """
  def left <= right, do: doc! [left, right]

  @doc """
  Binary `>=` operation.
  """
  def left >= right, do: doc! [left, right]

  @doc """
  Binary `<` operation.
  """
  def left < right, do: doc! [left, right]

  @doc """
  Binary `>` operation.
  """
  def left > right, do: doc! [left, right]

  @doc """
  Binary `+` operation.
  """
  def left + right, do: doc! [left, right]

  @doc """
  Binary `-` operation.
  """
  def left - right, do: doc! [left, right]

  @doc """
  Binary `*` operation.
  """
  def left * right, do: doc! [left, right]

  @doc """
  Binary `/` operation.
  """
  def left / right, do: doc! [left, right]

  @doc """
  Binary `and` operation.
  """
  def left and right, do: doc! [left, right]

  @doc """
  Binary `or` operation.
  """
  def left or right, do: doc! [left, right]

  @doc """
  Unary `not` operation.

  It is used to negate values in `:where`. It is also used to match
  the assert the opposite of `in/2`, `is_nil/1`, and `exists/1`.
  For example:

      from p in Post, where: p.id not in [1, 2, 3]

      from p in Post, where: not is_nil(p.title)

      # Retrieve all the posts that doesn't have comments.
      from p in Post,
        as: :post,
        where:
          not exists(
            from(
              c in Comment,
              where: parent_as(:post).id == c.post_id
            )
          )

  """
  def not(value), do: doc! [value]

  @doc """
  Checks if the left-value is included in the right one.

      from p in Post, where: p.id in [1, 2, 3]

  The right side may either be a list, a literal list
  or even a column in the database with array type:

      from p in Post, where: "elixir" in p.tags

  Additionally, the right side may also be a subquery:

      from c in Comment, where: c.post_id in subquery(
        from(p in Post, where: p.created_at > ^since)
      )
  """
  def left in right, do: doc! [left, right]

  @doc """
  Evaluates to true if the provided subquery returns 1 or more rows.

      from p in Post,
        as: :post,
        where:
          exists(
            from(
              c in Comment,
              where: parent_as(:post).id == c.post_id and c.replies_count > 5,
              select: 1
            )
          )

  This is best used in conjunction with `parent_as` to correlate the subquery
  with the parent query to test some condition on related rows in a different table.
  In the above example the query returns posts which have at least one comment that
  has more than 5 replies.
  """
  def exists(subquery), do: doc! [subquery]

  @doc """
  Tests whether one or more values returned from the provided subquery match in a comparison operation.

      from p in Product, where: p.id == any(
        from(li in LineItem, select: [li.product_id], where: li.created_at > ^since and li.qty >= 10)
      )

  A product matches in the above example if a line item was created since the provided date where the customer purchased
  at least 10 units.

  Both `any` and `all` must be given a subquery as an argument, and they must be used on the right hand side of a comparison.
  Both can be used with every comparison operator: `==`, `!=`, `>`, `>=`, `<`, `<=`.
  """
  def any(subquery), do: doc! [subquery]

  @doc """
  Evaluates whether all values returned from the provided subquery match in a comparison operation.

      from p in Post, where: p.visits >= all(
        from(p in Post, select: avg(p.visits), group_by: [p.category_id])
      )

  For a post to match in the above example it must be visited at least as much as the average post in all categories.

      from p in Post, where: p.visits == all(
        from(p in Post, select: max(p.visits))
      )

  The above example matches all the posts which are tied for being the most visited.

  Both `any` and `all` must be given a subquery as an argument, and they must be used on the right hand side of a comparison.
  Both can be used with every comparison operator: `==`, `!=`, `>`, `>=`, `<`, `<=`.
  """
  def all(subquery), do: doc! [subquery]

  @doc """
  Searches for `search` in `string`.

      from p in Post, where: like(p.body, "Chapter%")

  Translates to the underlying SQL LIKE query, therefore
  its behaviour is dependent on the database. In particular,
  PostgreSQL will do a case-sensitive operation, while the
  majority of other databases will be case-insensitive. For
  performing a case-insensitive `like` in PostgreSQL, see `ilike/2`.

  You should be very careful when allowing user sent data to be used
  as part of LIKE query, since they allow to perform
  [LIKE-injections](https://githubengineering.com/like-injection/).
  """
  def like(string, search), do: doc! [string, search]

  @doc """
  Searches for `search` in `string` in a case insensitive fashion.

      from p in Post, where: ilike(p.body, "Chapter%")

  Translates to the underlying SQL ILIKE query. This operation is
  only available on PostgreSQL.
  """
  def ilike(string, search), do: doc! [string, search]

  @doc """
  Checks if the given value is nil.

      from p in Post, where: is_nil(p.published_at)

  To check if a given value is not nil use:

      from p in Post, where: not is_nil(p.published_at)
  """
  def is_nil(value), do: doc! [value]

  @doc """
  Counts the entries in the table.

      from p in Post, select: count()
  """
  def count, do: doc! []

  @doc """
  Counts the given entry.

      from p in Post, select: count(p.id)
  """
  def count(value), do: doc! [value]

  @doc """
  Counts the distinct values in given entry.

      from p in Post, select: count(p.id, :distinct)
  """
  def count(value, :distinct), do: doc! [value, :distinct]

  @doc """
  Takes whichever value is not null, or null if they both are.

  In SQL, COALESCE takes any number of arguments, but in ecto
  it only takes two, so it must be chained to achieve the same
  effect.

      from p in Payment, select: p.value |> coalesce(p.backup_value) |> coalesce(0)
  """
  def coalesce(value, expr), do: doc! [value, expr]

  @doc """
  Applies the given expression as a FILTER clause against an
  aggregate. This is currently only supported by Postgres.

      from p in Payment, select: filter(avg(p.value), p.value > 0 and p.value < 100)

      from p in Payment, select: avg(p.value) |> filter(p.value < 0)
  """
  def filter(value, filter), do: doc! [value, filter]

  @doc """
  Calculates the average for the given entry.

      from p in Payment, select: avg(p.value)
  """
  def avg(value), do: doc! [value]

  @doc """
  Calculates the sum for the given entry.

      from p in Payment, select: sum(p.value)
  """
  def sum(value), do: doc! [value]

  @doc """
  Calculates the minimum for the given entry.

      from p in Payment, select: min(p.value)
  """
  def min(value), do: doc! [value]

  @doc """
  Calculates the maximum for the given entry.

      from p in Payment, select: max(p.value)
  """
  def max(value), do: doc! [value]

  @doc """
  Adds a given interval to a datetime.

  The first argument is a `datetime`, the second one is the count
  for the interval, which may be either positive or negative and
  the interval value:

      # Get all items published since the last month
      from p in Post, where: p.published_at >
                             datetime_add(^NaiveDateTime.utc_now(), -1, "month")

  In the example above, we used `datetime_add/3` to subtract one month
  from the current datetime and compared it with the `p.published_at`.
  If you want to perform operations on date, `date_add/3` could be used.

  See [Intervals](#module-intervals) for supported `interval` values.
  """
  def datetime_add(datetime, count, interval), do: doc! [datetime, count, interval]

  @doc """
  Adds a given interval to a date.

  See `datetime_add/3` for more information.

  See [Intervals](#module-intervals) for supported `interval` values.
  """
  def date_add(date, count, interval), do: doc! [date, count, interval]

  @doc """
  Adds the given interval to the current time in UTC.

  The current time in UTC is retrieved from Elixir and
  not from the database.

  See [Intervals](#module-intervals) for supported `interval` values.

  ## Examples

      from a in Account, where: a.expires_at < from_now(3, "month")

  """
  def from_now(count, interval), do: doc! [count, interval]

  @doc """
  Subtracts the given interval from the current time in UTC.

  The current time in UTC is retrieved from Elixir and
  not from the database.

  See [Intervals](#module-intervals) for supported `interval` values.

  ## Examples

      from p in Post, where: p.published_at > ago(3, "month")
  """
  def ago(count, interval), do: doc! [count, interval]

  @doc """
  Send fragments directly to the database.

  It is not possible to represent all possible database queries using
  Ecto's query syntax. When such is required, it is possible to use
  fragments to send any expression to the database:

      def unpublished_by_title(title) do
        from p in Post,
          where: is_nil(p.published_at) and
                 fragment("lower(?)", p.title) == ^title
      end

  Every occurrence of the `?` character will be interpreted as a place
  for parameters, which must be given as additional arguments to
  `fragment`. If the literal character `?` is required as part of the
  fragment, it can be escaped with `\\\\?` (one escape for strings,
  another for fragment).

  In the example above, we are using the lower procedure in the
  database to downcase the title column.

  It is very important to keep in mind that Ecto is unable to do any
  type casting when fragments are used. Therefore it may be necessary
  to explicitly cast parameters via `type/2`:

      fragment("lower(?)", p.title) == type(^title, :string)

  ## Literals

  Sometimes you need to interpolate a literal value into a fragment,
  instead of a parameter. For example, you may need to pass a table
  name or a collation, such as:

      collation = "es_ES"
      fragment("? COLLATE ?", ^name, ^collation)

  The example above won't work because `collation` will be passed
  as a parameter, while it has to be a literal part of the query.

  You can address this by telling Ecto that variable is a literal:

      fragment("? COLLATE ?", ^name, literal(^collation))

  Ecto will then escape it and make it part of the query.

  > #### Literals and query caching {: .warning}
  >
  > Because literals are made part of the query, each interpolated
  > literal will generate a separate query, with its own cache.

  ## Defining custom functions using macros and fragment

  You can add a custom Ecto query function using macros.  For example
  to expose SQL's coalesce function you can define this macro:

      defmodule CustomFunctions do
        defmacro coalesce(left, right) do
          quote do
            fragment("coalesce(?, ?)", unquote(left), unquote(right))
          end
        end
      end

  To have coalesce/2 available, just import the module that defines it.

      import CustomFunctions

  The only downside is that it will show up as a fragment when
  inspecting the Elixir query.  Other than that, it should be
  equivalent to a built-in Ecto query function.

  ## Keyword fragments

  In order to support databases that do not have string-based
  queries, like MongoDB, fragments also allow keywords to be given:

      from p in Post,
          where: fragment(title: ["$eq": ^some_value])

  """
  def fragment(fragments), do: doc! [fragments]

  @doc """
  Allows a field to be dynamically accessed.

      def at_least_four(doors_or_tires) do
        from c in Car,
          where: field(c, ^doors_or_tires) >= 4
      end

  In the example above, both `at_least_four(:doors)` and `at_least_four(:tires)`
  would be valid calls as the field is dynamically generated.
  """
  def field(source, field), do: doc! [source, field]

  @doc """
  Used in `select` to specify which struct fields should be returned.

  For example, if you don't need all fields to be returned
  as part of a struct, you can filter it to include only certain
  fields by using `struct/2`:

      from p in Post,
        select: struct(p, [:title, :body])

  `struct/2` can also be used to dynamically select fields:

      fields = [:title, :body]
      from p in Post, select: struct(p, ^fields)

  As a convenience, `select` allows developers to take fields
  without an explicit call to `struct/2`:

      from p in Post, select: [:title, :body]

  Or even dynamically:

      fields = [:title, :body]
      from p in Post, select: ^fields

  For preloads, the selected fields may be specified from the parent:

      from(city in City, preload: :country,
           select: struct(city, [:country_id, :name, country: [:id, :population]]))

  If the same source is selected multiple times with a `struct`,
  the fields are merged in order to avoid fetching multiple copies
  from the database. In other words, the expression below:

      from(city in City, preload: :country,
           select: {struct(city, [:country_id]), struct(city, [:name])})

  is expanded to:

      from(city in City, preload: :country,
           select: {struct(city, [:country_id, :name]), struct(city, [:country_id, :name])})

  **IMPORTANT**: When filtering fields for associations, you
  MUST include the foreign keys used in the relationship,
  otherwise Ecto will be unable to find associated records.
  """
  def struct(source, fields), do: doc! [source, fields]

  @doc """
  Used in `select` to specify which fields should be returned as a map.

  For example, if you don't need all fields to be returned or
  neither need a struct, you can use `map/2` to achieve both:

      from p in Post,
        select: map(p, [:title, :body])

  `map/2` can also be used to dynamically select fields:

      fields = [:title, :body]
      from p in Post, select: map(p, ^fields)

  If the same source is selected multiple times with a `map`,
  the fields are merged in order to avoid fetching multiple copies
  from the database. In other words, the expression below:

      from(city in City, preload: :country,
           select: {map(city, [:country_id]), map(city, [:name])})

  is expanded to:

      from(city in City, preload: :country,
           select: {map(city, [:country_id, :name]), map(city, [:country_id, :name])})

  For preloads, the selected fields may be specified from the parent:

      from(city in City, preload: :country,
           select: map(city, [:country_id, :name, country: [:id, :population]]))

   It's also possible to select a struct from one source but only a subset of
   fields from one of its associations:

      from(city in City, preload: :country,
           select: %{city | country: map(country: [:id, :population])})

  **IMPORTANT**: When filtering fields for associations, you
  MUST include the foreign keys used in the relationship,
  otherwise Ecto will be unable to find associated records.
  """
  def map(source, fields), do: doc! [source, fields]

  @doc """
  Merges the map on the right over the map on the left.

  If the map on the left side is a struct, Ecto will check
  all of the field on the right previously exist on the left
  before merging.

      from(city in City, select: merge(city, %{virtual_field: "some_value"}))

  This function is primarily used by `Ecto.Query.select_merge/3`
  to merge different select clauses.
  """
  def merge(left_map, right_map), do: doc! [left_map, right_map]

  @doc """
  Returns value from the `json_field` pointed to by `path`.

      from(post in Post, select: json_extract_path(post.meta, ["author", "name"]))

  The query can be also rewritten as:

      from(post in Post, select: post.meta["author"]["name"])

  Path elements can be integers to access values in JSON arrays:

      from(post in Post, select: post.meta["tags"][0]["name"])

  Any element of the path can be dynamic:

      field = "name"
      from(post in Post, select: post.meta["author"][^field])

  ## Warning: indexes on PostgreSQL

  PostgreSQL supports indexing on jsonb columns via GIN indexes.
  Whenever comparing the value of a jsonb field against a string
  or integer, Ecto will use the containement operator @> which
  is optimized. You can even use the more efficient `jsonb_path_ops`
  GIN index variant. For more information, consult PostgreSQL's docs
  on [JSON indexing](https://www.postgresql.org/docs/current/datatype-json.html#JSON-INDEXING).

  ## Warning: return types

  The underlying data in the JSON column is returned without any
  additional decoding. This means "null" JSON values are not the
  same as SQL's "null". For example, the `Repo.all` operation below
  returns an empty list because `p.meta["author"]` returns JSON's
  null and therefore `is_nil` does not succeed:

      Repo.insert!(%Post{meta: %{author: nil}})
      Repo.all(from(post in Post, where: is_nil(p.meta["author"])))

  Similarly, other types, such as datetimes, are returned as strings.
  This means conditions like `post.meta["published_at"] > from_now(-1, "day")`
  may return incorrect results or fail as the underlying database
  tries to compare incompatible types. You can, however, use `type/2`
  to force the types on the database level.
  """
  def json_extract_path(json_field, path), do: doc! [json_field, path]

  @doc """
  Casts the given value to the given type at the database level.

  Most of the times, Ecto is able to proper cast interpolated
  values due to its type checking mechanism. In some situations
  though, you may want to tell Ecto that a parameter has some
  particular type:

      type(^title, :string)

  It is also possible to say the type must match the same of a column:

      type(^title, p.title)

  Or a parameterized type, which must be previously initialized
  with `Ecto.ParameterizedType.init/2`:

      @my_enum Ecto.ParameterizedType.init(Ecto.Enum, values: [:foo, :bar, :baz])
      type(^title, ^@my_enum)

  Ecto will ensure `^title` is cast to the given type and enforce such
  type at the database level. If the value is returned in a `select`,
  Ecto will also enforce the proper type throughout.

  When performing arithmetic operations, `type/2` can be used to cast
  all the parameters in the operation to the same type:

      from p in Post,
        select: type(p.visits + ^a_float + ^a_integer, :decimal)

  Inside `select`, `type/2` can also be used to cast fragments:

      type(fragment("NOW"), :naive_datetime)

  Or to type fields from schemaless queries:

      from p in "posts", select: type(p.cost, :decimal)

  Or to type aggregation results:

      from p in Post, select: type(avg(p.cost), :integer)
      from p in Post, select: type(filter(avg(p.cost), p.cost > 0), :integer)

  Or to type comparison expression results:

      from p in Post, select: type(coalesce(p.cost, 0), :integer)

  Or to type fields from a parent query using `parent_as/1`:

      child = from c in Comment, where: type(parent_as(:posts).id, :string) == c.text
      from Post, as: :posts, inner_lateral_join: c in subquery(child), select: c.text

  """
  def type(interpolated_value, type), do: doc! [interpolated_value, type]

  @doc """
  Refer to a named atom binding.

  See the "Named binding" section in `Ecto.Query` for more information.
  """
  def as(binding), do: doc! [binding]

  @doc """
  Refer to a named atom binding in the parent query.

  This is available only inside subqueries.

  See the "Named binding" section in `Ecto.Query` for more information.
  """
  def parent_as(binding), do: doc! [binding]

  @doc """
  Refer to an alias of a selected value.

  This can be used to refer to aliases created using `selected_as/2`. If
  the alias hasn't been created using `selected_as/2`, an error will be raised.

  Each database has its own rules governing which clauses can reference these aliases.
  If an error is raised mentioning an unknown column, most likely the alias is being
  referenced somewhere that is not allowed. Consult the documentation for the database
  to ensure the alias is being referenced correctly.
  """
  def selected_as(name), do: doc! [name]

  @doc """
  Creates an alias for the given selected value.

  When working with calculated values, an alias can be used to simplify
  the query. Otherwise, the entire expression would need to be copied when
  referencing it outside of select statements.

  This comes in handy when, for instance, you would like to use the calculated
  value in `Ecto.Query.group_by/3` or `Ecto.Query.order_by/3`:

      from p in Post,
        select: %{
          posted: selected_as(p.posted, :date),
          sum_visits: p.visits |> coalesce(0) |> sum() |> selected_as(:sum_visits)
        },
        group_by: selected_as(:date),
        order_by: selected_as(:sum_visits)

  The name of the alias must be an atom and it can only be used in the outer most
  select expression, otherwise an error is raised. Please note that the alias name
  does not have to match the key when `select` returns a map, struct or keyword list.

  Using this in conjunction with `selected_as/1` is recommended to ensure only defined aliases
  are referenced.

  ## Subqueries and CTEs

  Subqueries and CTEs automatically alias the selected fields, for example, one can write:

      # Subquery
      s = from p in Post, select: %{visits: coalesce(p.visits, 0)}
      from(s in subquery(s), select: s.visits)

      # CTE
      cte_query = from p in Post, select: %{visits: coalesce(p.visits, 0)}
      Post |> with_cte("cte", as: ^cte_query) |> join(:inner, [p], c in "cte") |> select([p, c], c.visits)

  However, one can also use `selected_as` to override the default naming:

      # Subquery
      s = from p in Post, select: %{visits: coalesce(p.visits, 0) |> selected_as(:num_visits)}
      from(s in subquery(s), select: s.num_visits)

      # CTE
      cte_query = from p in Post, select: %{visits: coalesce(p.visits, 0) |> selected_as(:num_visits)}
      Post |> with_cte("cte", as: ^cte_query) |> join(:inner, [p], c in "cte") |> select([p, c], c.num_visits)

  The name given to `selected_as/2` can also be referenced in `selected_as/1`,
  as in regular queries.
  """
  def selected_as(selected_value, name), do: doc! [selected_value, name]

  defp doc!(_) do
    raise "the functions in Ecto.Query.API should not be invoked directly, " <>
          "they serve for documentation purposes only"
  end
end
