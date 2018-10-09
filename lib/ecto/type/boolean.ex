defmodule Ecto.Type.Boolean do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :boolean

  def cast(term) when is_boolean(term), do: {:ok, term}
  def cast(term) when term in ~w(true 1), do: {:ok, true}
  def cast(term) when term in ~w(false 0), do: {:ok, false}
  def cast(_), do: :error

  def dump(term) when is_boolean(term), do: {:ok, term}
  def dump(_), do: :error

  def load(term) when is_boolean(term), do: {:ok, term}
  def load(_), do: :error

  def equal?(term, term) when is_boolean(term), do: true
  def equal?(_, _), do: false
end
