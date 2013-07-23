defprotocol Ecto.Queryable do
  @only [Record, Atom]
  def to_query(expr)
end

defimpl Ecto.Queryable, for: Ecto.Query.Query do
  def to_query(query), do: query
end

defimpl Ecto.Queryable, for: Atom do
  def to_query(module) do
    # TODO: Should we check here if module is an Entity?
    Ecto.Query.Query[froms: [module]]
  end
end
