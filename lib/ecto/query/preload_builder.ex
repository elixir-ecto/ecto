defmodule Ecto.Query.PreloadBuilder do
  @reason "preload should be given a single atom or a list of atoms"

  def validate(list) when is_list(list) do
    Enum.map(list, fn elem ->
      unless is_atom(elem) do
        raise Ecto.InvalidQuery, reason: @reason
      end
    end)
  end

  def validate(_other), do: raise(Ecto.InvalidQuery, reason: @reason)
end
