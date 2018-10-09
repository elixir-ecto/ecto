defmodule Ecto.Type.Id do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :id

  def cast(term) when is_integer(term), do: {:ok, term}

  def cast(term) when is_binary(term) do
    case Integer.parse(term) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  def cast(_), do: :error

  def dump(term) when is_integer(term), do: {:ok, term}
  def dump(_), do: :error

  def load(term) when is_integer(term), do: {:ok, term}
  def load(_), do: :error

  def equal?(term, term) when is_integer(term), do: true
  def equal?(_, _), do: false
end
