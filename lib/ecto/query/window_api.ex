defmodule Ecto.Query.WindowAPI do
  @moduledoc """
  Lists all windows functions.

  Windows functions must always be used as the first argument
  of `over/2` where the second argument is the name of a window:

      from e in Employee,
        select: {e.depname, e.empno, e.salary, over(avg(e.salary), :department)},
        windows: [department: [partition_by: e.depname]]

  In the example above, we get the average salary per department.
  `:department` is the window name, partitioned by `e.depname`
  and `avg/1` is the window function.

  However, note that defining a window is not necessary, as the
  window definition can be given as the second argument to `over`:

      from e in Employee,
        select: {e.depname, e.empno, e.salary, over(avg(e.salary), partition_by: e.depname)}

  Both queries are equivalent. However, if you are using the same
  partitioning over and over again, defining a window will reduce
  the query size. See `Ecto.Query.windows/3` for all possible window
  expressions, such as `:partition_by` and `:order_by`.
  """

  @dialyzer :no_return

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
  Returns number of the current row within its partition, counting from 1.

      from p in Post,
           select: row_number() |> over(partition_by: p.category_id, order_by: p.date)

  Note that this function must be invoked using window function syntax.
  """
  def row_number(), do: doc! []

  @doc """
  Returns rank of the current row with gaps; same as `row_number/0` of its first peer.

      from p in Post,
           select: rank() |> over(partition_by: p.category_id, order_by: p.date)

  Note that this function must be invoked using window function syntax.
  """
  def rank(), do: doc! []

  @doc """
  Returns rank of the current row without gaps; this function counts peer groups.

      from p in Post,
           select: dense_rank() |> over(partition_by: p.category_id, order_by: p.date)

  Note that this function must be invoked using window function syntax.
  """
  def dense_rank(), do: doc! []

  @doc """
  Returns relative rank of the current row: (rank - 1) / (total rows - 1).

      from p in Post,
           select: percent_rank() |> over(partition_by: p.category_id, order_by: p.date)

  Note that this function must be invoked using window function syntax.
  """
  def percent_rank(), do: doc! []

  @doc """
  Returns relative rank of the current row:
  (number of rows preceding or peer with current row) / (total rows).

      from p in Post,
           select: cume_dist() |> over(partition_by: p.category_id, order_by: p.date)

  Note that this function must be invoked using window function syntax.
  """
  def cume_dist(), do: doc! []

  @doc """
  Returns integer ranging from 1 to the argument value, dividing the partition as equally as possible.

      from p in Post,
           select: ntile(10) |> over(partition_by: p.category_id, order_by: p.date)

  Note that this function must be invoked using window function syntax.
  """
  def ntile(num_buckets), do: doc! [num_buckets]

  @doc """
  Returns value evaluated at the row that is the first row of the window frame.

      from p in Post,
           select: first_value(p.id) |> over(partition_by: p.category_id, order_by: p.date)

  Note that this function must be invoked using window function syntax.
  """
  def first_value(value), do: doc! [value]

  @doc """
  Returns value evaluated at the row that is the last row of the window frame.

      from p in Post,
           select: last_value(p.id) |> over(partition_by: p.category_id, order_by: p.date)

  Note that this function must be invoked using window function syntax.
  """
  def last_value(value), do: doc! [value]


  @doc """
  Applies the given expression as a FILTER clause against an
  aggregate. This is currently only supported by Postgres.

      from p in Post,
           select: avg(p.value)
                   |> filter(p.value > 0 and p.value < 100)
                   |> over(partition_by: p.category_id, order_by: p.date)
  """

  def filter(value, filter), do: doc! [value, filter]

  @doc """
  Returns value evaluated at the row that is the nth row of the window
  frame (counting from 1); `nil` if no such row.

      from p in Post,
           select: nth_value(p.id, 4) |> over(partition_by: p.category_id, order_by: p.date)

  Note that this function must be invoked using window function syntax.
  """
  def nth_value(value, nth), do: doc! [value, nth]

  @doc """
  Returns value evaluated at the row that is offset rows before
  the current row within the partition.

  If there is no such row, instead return default (which must be of the
  same type as value). Both offset and default are evaluated with respect
  to the current row. If omitted, offset defaults to 1 and default to `nil`.

      from e in Events,
           windows: [w: [partition_by: e.name, order_by: e.tick]],
           select: {
             e.tick,
             e.action,
             e.name,
             lag(e.action) |> over(:w), # previous_action
             lead(e.action) |> over(:w) # next_action
           }

  Note that this function must be invoked using window function syntax.
  """
  def lag(value, offset \\ 1, default \\ nil), do: doc! [value, offset, default]

  @doc """
  Returns value evaluated at the row that is offset rows after
  the current row within the partition.

  If there is no such row, instead return default (which must be of the
  same type as value). Both offset and default are evaluated with respect
  to the current row. If omitted, offset defaults to 1 and default to `nil`.

      from e in Events,
           windows: [w: [partition_by: e.name, order_by: e.tick],
           select: {
             e.tick,
             e.action,
             e.name,
             lag(e.action) |> over(:w), # previous_action
             lead(e.action) |> over(:w) # next_action
           }

  Note that this function must be invoked using window function syntax.
  """
  def lead(value, offset \\ 1, default \\ nil), do: doc! [value, offset, default]

  defp doc!(_) do
    raise "the functions in Ecto.Query.WindowAPI should not be invoked directly, " <>
          "they serve for documentation purposes only"
  end
end
