defmodule Ecto.Adapters.Postgres.TypeMap do
  def for(:string), do: :text
  def for(:binary), do: :text
  def for(:datetime), do: :timestamp
  def for(type), do: type
end
