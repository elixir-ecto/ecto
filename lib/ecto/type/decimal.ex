defmodule Ecto.Type.Decimal do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :decimal

  def cast(term) when is_binary(term) do
    case Decimal.parse(term) do
      {:ok, decimal} -> dump(decimal)
      :error -> :error
    end
  end

  def cast(term), do: dump(term)

  def dump(term) when is_integer(term), do: {:ok, Decimal.new(term)}
  def dump(term) when is_float(term), do: {:ok, Decimal.from_float(term)}
  def dump(%Decimal{coef: coef}) when coef in [:inf, :qNaN, :sNaN], do: :error
  def dump(%Decimal{} = term), do: {:ok, term}
  def dump(_), do: :error

  def load(term), do: dump(term)

  def equal?(%Decimal{} = a, %Decimal{} = b), do: Decimal.equal?(a, b)
  def equal?(_, _), do: false
end
