defmodule Ecto.PostgresDateRange do
  @moduledoc """
  An ecto type for postgrex daterange.
  """
  @behaviour Ecto.Type

  alias Ecto.DiscreteRange

  defstruct [:lower, :upper]

  @impl true
  def type, do: :daterange

  @type t :: %__MODULE__{}

  @doc """
  Creates a new date range. The `lower` value must the less or equal
  than the `upper` value. The default is to create an `closed-open`
  interval but you can use any variant as long as don't break the
  less-or-equal than invariant.
  """
  @spec new(Date.t() | String.t(), Date.t() | String.t(), {:open | :closed, :open | :closed}) ::
          {:ok, t} | :error
  def new(lower, upper, mode \\ {:closed, :open}) do
    with {:ok, {lower, upper}} <-
           DiscreteRange.new(succ_fn(), comp_fn(), :date, lower, upper, mode) do
      {:ok, %__MODULE__{lower: lower, upper: upper}}
    end
  end

  @doc """
  Bang version of the `new/3` and `new/4` functions.
  """
  @spec new(Date.t() | String.t(), Date.t() | String.t(), {:open | :closed, :open | :closed}) :: t
  def new!(lower, upper, mode \\ {:closed, :open}) do
    {:ok, range} = new(lower, upper, mode)
    range
  end

  @impl true
  def cast(value) do
    case value do
      %__MODULE__{} ->
        {:ok, value}

      _ when is_binary(value) ->
        with {:ok, {lower, upper}} <- DiscreteRange.cast(succ_fn(), comp_fn(), :date, value) do
          {:ok, %__MODULE__{lower: lower, upper: upper}}
        end

      _ ->
        :error
    end
  end

  @impl true
  def dump(value) do
    case value do
      %__MODULE__{} ->
        DiscreteRange.dump(:date, value.lower, value.upper)

      _ ->
        :error
    end
  end

  @impl true
  def load(value) do
    with {:ok, {lower, upper}} <- DiscreteRange.load(succ_fn(), :date, value) do
      {:ok, %__MODULE__{lower: lower, upper: upper}}
    end
  end

  @doc """
  Compute the allen relationship between two date intervals. Refer to
  `Ecto.DiscreteRange.relation` for more information.

  Examples:

      iex> relation(new!(~D[1900-01-01], ~D[1900-02-01]), new!(~D[1900-01-20], ~D[1900-02-10]))
      :overlaps
  """
  @spec relation(t, t) :: DiscreteRange.allens_relation()
  def relation(a = %__MODULE__{}, b = %__MODULE__{}) do
    DiscreteRange.relation(comp_fn(), a.lower, a.upper, b.lower, b.upper)
  end

  @doc """
  Membership check. Checks if the interval contains a date.

  Examples:

      iex> contains?(new!(~D[1900-01-01], ~D[1900-01-02]), ~D[1900-01-01])
      true
      iex> contains?(new!(~D[1900-01-01], ~D[1900-01-02]), ~D[1900-01-02])
      false
  """
  @spec contains?(t, Date.t()) :: boolean
  def contains?(a = %__MODULE__{}, x = %Date{}) do
    DiscreteRange.contains?(comp_fn(), a.lower, a.upper, x)
  end

  defp comp_fn, do: &Date.compare/2

  defp succ_fn, do: fn date -> Date.add(date, 1) end
end
