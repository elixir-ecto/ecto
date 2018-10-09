defmodule Ecto.Type.Float do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :float

  def cast(term) when is_float(term), do: {:ok, term}
  def cast(term) when is_integer(term), do: {:ok, :erlang.float(term)}

  def cast(term) when is_binary(term) do
    case Float.parse(term) do
      {float, ""} -> {:ok, float}
      _ -> :error
    end
  end

  def cast(_), do: :error

  def dump(term) when is_float(term), do: {:ok, term}
  def dump(_), do: :error

  def load(term) when is_float(term), do: {:ok, term}
  def load(term) when is_integer(term), do: {:ok, :erlang.float(term)}
  def load(_), do: :error

  def equal?(term, term) when is_float(term), do: true
  def equal?(_, _), do: false
end
