defmodule Ecto.Query.API do
  @moduledoc """
  This module lists all functions allowed in the query API.

    * Comparison operators: `==`, `!=`, `<=`, `>=`, `<`, `>`
    * Boolean operators: `and`, `or`, `not`
    * Inclusion operator: `in/2`
    * Search functions: `like/2` and `ilike/2`
    * Null check functions: `is_nil/1`
    * Aggregates: `count/1`, `avg/1`, `sum/1`, `min/1`, `max/1`
    * Date/time intervals: `datetime_add/3`, `date_add/3`, `from_now/2`, `ago/2`
    * Inside select: `struct/2`, `map/2` and literals (map, tuples, lists, etc)
    * General: `fragment/1`, `field/2` and `type/2`

  Note the functions in this module exist for documentation
  purposes and one should never need to invoke them directly.
  Furthermore, it is possible to define your own macros and
  use them in Ecto queries (see docs for `fragment/1`).
  """

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
  Binary `and` operation.
  """
  def left and right, do: doc! [left, right]

  @doc """
  Binary `or` operation.
  """
  def left or right, do: doc! [left, right]

  @doc """
  Unary `not` operation.
  """
  def not(value), do: doc! [value]

  @doc """
  Checks if the left-value is included in the right one.

      from p in Post, where: p.id in [1, 2, 3]

  The right side may either be a list, a literal list
  or even a column in the database with array type:

      from p in Post, where: "elixir" in p.tags
  """
  def left in right, do: doc! [left, right]

  @doc """
  Searches for `search` in `string`.

      from p in Post, where: like(p.body, "Chapter%")

  Translates to the underlying SQL LIKE query, therefore
  its behaviour is dependent on the database. In particular,
  PostgreSQL will do a case-sensitive operation, while the
  majority of other databases will be case-insensitive. For
  performing a case-insensitive `like` in PostgreSQL, see `ilike/2`.
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
  """
  def is_nil(value), do: doc! [value]

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
                             datetime_add(^Ecto.DateTime.utc, -1, "month")

  In the example above, we used `datetime_add/3` to subtract one month
  from the current datetime and compared it with the `p.published_at`.
  If you want to perform operations on date, `date_add/3` could be used.

  The following intervals are supported: year, month, week, day, hour,
  minute, second, millisecond and microsecond.
  """
  def datetime_add(datetime, count, interval), do: doc! [datetime, count, interval]

  @doc """
  Adds a given interval to a date.

  See `datetime_add/3` for more information.
  """
  def date_add(date, count, interval), do: doc! [date, count, interval]

  @doc """
  Adds the given interval to the current time in UTC.

  The current time in UTC is retrieved from Elixir and
  not from the database.

  ## Examples

      from a in Account, where: a.expires_at < from_now(3, "month")

  """
  def from_now(count, interval), do: doc! [count, interval]

  @doc """
  Substracts the given interval from the current time in UTC.

  The current time in UTC is retrieved from Elixir and
  not from the database.

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

  In the example above, we are using the lower procedure in the
  database to downcase the title column.

  It is very important to keep in mind that Ecto is unable to do any
  type casting described above when fragments are used. You can
  however use the `type/2` function to give Ecto some hints:

      fragment("lower(?)", p.title) == type(^title, :string)

  Or even say the right side is of the same type as `p.title`:

      fragment("lower(?)", p.title) == type(^title, p.title)

  It is possible to make use of PostgreSQL's JSON/JSONB data type
  with fragments, as well:

      fragment("?->>? ILIKE ?", p.map, "key_name", ^some_value)

  ## Keyword fragments

  In order to support databases that do not have string-based
  queries, like MongoDB, fragments also allow keywords to be given:

      from p in Post,
          where: fragment(title: ["$eq": ^some_value])

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

  However, `struct/2` is still useful when you want to limit
  the fields of different structs:

      from(city in City, join: country in assoc(city, :country),
           select: {struct(city, [:country_id, :name]), struct(country, [:id, :population])}

  For preloads, the selected fields may be specified from the parent:

      from(city in City, preload: :country,
           select: struct(city, [:country_id, :name, country: [:id, :population]]))

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

  `map/2` is also useful when you want to limit the fields
  of different structs:

      from(city in City, join: country in assoc(city, :country),
           select: {map(city, [:country_id, :name]), map(country, [:id, :population])}

  For preloads, the selected fields may be specified from the parent:

      from(city in City, preload: :country,
           select: map(city, [:country_id, :name, country: [:id, :population]]))

  **IMPORTANT**: When filtering fields for associations, you
  MUST include the foreign keys used in the relationship,
  otherwise Ecto will be unable to find associated records.
  """
  def map(source, fields), do: doc! [source, fields]

  @doc """
  Casts the given value to the given type.

  Most of the times, Ecto is able to proper cast interpolated
  values due to its type checking mechanism. In some situations
  though, in particular when using fragments with `fragment/1`,
  you may want to tell Ecto you are expecting a particular type:

      fragment("lower(?)", p.title) == type(^title, :string)

  It is also possible to say the type must match the same of a column:

      fragment("lower(?)", p.title) == type(^title, p.title)
  """
  def type(interpolated_value, type), do: doc! [interpolated_value, type]

  defp doc!(_) do
    raise "the functions in Ecto.Query.API should not be invoked directly, " <>
          "they serve for documentation purposes only"
  end
end
