defrecord Ecto.Reflections.HasMany, [:field, :owner, :associated, :foreign_key]

defrecord Ecto.Associations.HasMany, [:__loaded__, :__target__, :__name__] do
  alias Ecto.Associations.HasMany

  def new(params // [], HasMany[__target__: target, __name__: name]) do
    refl = elem(target, 0).__ecto__(:association, name)
    fk = refl.foreign_key
    refl.associated.new([{ fk, target.primary_key }] ++ params)
  end

  def to_list(HasMany[__loaded__: nil, __target__: target, __name__: name]) do
    refl = elem(target, 0).__ecto__(:association, name)
    raise Ecto.AssociationNotLoadedError,
      type: :has_many, owner: refl.owner, name: name
  end

  def to_list(HasMany[__loaded__: loaded]) do
    loaded
  end
end

defimpl Ecto.Queryable, for: Ecto.Associations.HasMany do
  alias Ecto.Associations.HasMany
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr

  def to_query(HasMany[__target__: target, __name__: name]) do
    refl = elem(target, 0).__ecto__(:association, name)

    pk = target.primary_key
    fk = refl.foreign_key

    from = refl.associated
    where_expr = quote do &0.unquote(fk) == unquote(pk) end
    where = QueryExpr[expr: where_expr]
    Query[from: from, wheres: [where]]
  end
end

defimpl Enumerable, for: Ecto.Associations.HasMany do
  def count(assoc), do: length(assoc.to_list)
  def member?(assoc, value), do: value in assoc.to_list
  def reduce(assoc, acc, fun), do: Enumerable.List.reduce(assoc.to_list, acc, fun)
end
