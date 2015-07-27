defmodule Ecto.Query.API do
  @moduledoc """
  This module lists all functions allowed in the query API.

    * Comparison operators: `==`, `!=`, `<=`, `>=`, `<`, `>`
    * Boolean operators: `and`, `or`, `not`
    * Inclusion operator: `in/2`
    * Search functions: `like/2` and `ilike/2`
    * Null check functions: `is_nil/1`
    * Aggregates: `count/1`, `avg/1`, `sum/1`, `min/1`, `max/1`
    * Date/time intervals: `datetime_add/3`, `date_add/3`
    * General: `fragment/1`, `field/2` and `type/2`

  Note the functions in this module exist for documentation
  purposes and one should never need to invoke them directly.
  Furthermore, it is possible to define your own macros and
  use them in Ecto queries.
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

  Translates to the underlying SQL LIKE query.

      from p in Post, where: like(p.body, "Chapter%")
  """
  def like(string, search), do: doc! [string, search]

  @doc """
  Searches for `search` in `string` in a case insensitive fashion.

  Translates to the underlying SQL ILIKE query.

      from p in Post, where: ilike(p.body, "Chapter%")
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
  Calculates the minimum for the given entry.

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
  Send fragments directly to the database.

  It is not possible to represent all possible database queries using
  Ecto's query syntax. When such is required, it is possible to use
  fragments to send any expression to the database:

      def unpublished_by_title(title) do
        from p in Post,
          where: is_nil(p.published_at) and
                 fragment("downcase(?)", p.title) == ^title
      end

  In the example above, we are using the downcase procedure in the
  database to downcase the title column.

  It is very important to keep in mind that Ecto is unable to do any
  type casting described above when fragments are used. You can
  however use the `type/2` function to give Ecto some hints:

      fragment("downcase(?)", p.title) == type(^title, :string)

  Or even say the right side is of the same type as `p.title`:

      fragment("downcase(?)", p.title) == type(^title, p.title)

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
  Casts the given value to the given type.

  Most of the times, Ecto is able to proper cast interpolated
  values due to its type checking mechanism. In some situations
  though, in particular when using fragments with `fragment/1`,
  you may want to tell Ecto you are expecting a particular type:

      fragment("downcase(?)", p.title) == type(^title, :string)

  It is also possible to say the type must match the same of a column:

      fragment("downcase(?)", p.title) == type(^title, p.title)
  """
  def type(interpolated_value, type), do: doc! [interpolated_value, type]

  defp doc!(_) do
    raise "the functions in Ecto.Query.API should not be invoked directly, " <>
          "they serve for documentation purposes only"
  end
end
