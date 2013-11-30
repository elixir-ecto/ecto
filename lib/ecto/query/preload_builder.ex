defmodule Ecto.Query.PreloadBuilder do
  @moduledoc false

  @reason "preload should be given a single atom or a list of atoms"

  def validate(list) when is_list(list) do
    Enum.each(list, fn elem ->
      validate(elem)
    end)
  end

  def validate({ atom, list }) when is_atom(atom) do
    validate(list)
  end

  def validate(atom) when is_atom(atom), do: :ok
  def validate(_other), do: raise(Ecto.QueryError, reason: @reason)
end
