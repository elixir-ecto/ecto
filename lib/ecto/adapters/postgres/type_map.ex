defmodule Ecto.Adapters.Postgres.TypeMap do
  def for(type) when is_binary(type), do: for binary_to_atom(type)
  def for(:string), do: :text
  def for(:binary), do: :text
  def for(:datetime), do: :timestamp
  def for(type), do: type
end
