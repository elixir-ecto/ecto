defmodule Ecto.Query.Util do
  @moduledoc false

  # TODO: Get rid of me

  @doc """
  Look up a source with a variable.
  """
  def find_source(sources, {:&, _, [ix]}) when is_tuple(sources) do
    elem(sources, ix)
  end

  @doc "Returns the source from a source tuple."
  def source({source, _model}), do: source

  @doc "Returns model from a source tuple or nil if there is none."
  def model({_source, model}), do: model
end
