defprotocol Ecto.Queryable do
  @moduledoc """
  The `Queryable` protocol is responsible for converting a structure to an
  `Ecto.Query.Query` record. The only function required to implement is
  `to_query` which does the conversion.
  """

  def to_query(expr)
end

defimpl Ecto.Queryable, for: Ecto.Query.Query do
  def to_query(query), do: query
end

defimpl Ecto.Queryable, for: Atom do
  def to_query(module) do
    try do
      module.__model__(:name)
      Ecto.Query.Query[from: module]
    rescue
      UndefinedFunctionError ->
        raise Protocol.UndefinedError,
             protocol: @protocol,
                value: module,
          description: "the given module/atom is not a model"
    end
  end
end
