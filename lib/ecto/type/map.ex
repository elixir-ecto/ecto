defmodule Ecto.Type.Map do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :map

  def cast(term) when is_map(term), do: {:ok, term}
  def cast(_), do: :error

  def dump(term) when is_map(term), do: {:ok, term}
  def dump(_), do: :error

  def load(term) when is_map(term), do: {:ok, term}
  def load(_), do: :error

  def equal?(term, term) when is_map(term), do: true
  def equal?(_, _), do: false
end
