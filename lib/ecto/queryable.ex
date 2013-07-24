defprotocol Ecto.Queryable do
  @only [Record, Atom]
  def to_query(expr)
end

defimpl Ecto.Queryable, for: Ecto.Query.Query do
  def to_query(query), do: query
end

defimpl Ecto.Queryable, for: Atom do
  def to_query(module) do
    try do
      module.__ecto__(:dataset)
      Ecto.Query.Query[froms: [module]]
    rescue
      UndefinedFunctionError ->
        raise Protocol.UndefinedError,
                 protocol: @protocol,
                    value: module,
              description: "the given atom is not an entity"
    end
  end
end
