defrecord Ecto.Reflections.HasMany, [:field, :owner, :associated, :foreign_key]

defmodule Ecto.Associations.HasMany do
  # Needs to be defrecordp because we don't want pollute the module
  # with functions generated for the record

  defrecordp :assoc, __MODULE__, [:loaded, :target, :name]

  def new(params // [], assoc(target: target, name: name)) do
    refl = elem(target, 0).__ecto__(:association, name)
    fk = refl.foreign_key
    refl.associated.new([{ fk, target.primary_key }] ++ params)
  end

  def to_list(assoc(loaded: nil, target: target, name: name)) do
    refl = elem(target, 0).__ecto__(:association, name)
    raise Ecto.AssociationNotLoadedError,
      type: :has_many, owner: refl.owner, name: name
  end

  def to_list(assoc(loaded: loaded)) do
    loaded
  end

  Enum.each [:loaded, :target, :name], fn field ->
    def __ecto__(unquote(field), record) do
      assoc(record, unquote(field))
    end

    def __ecto__(unquote(field), value, record) do
      assoc(record, [{ unquote(field), value }])
    end
  end

  def __ecto__(:new, name) do
    assoc(name: name)
  end
end

defimpl Ecto.Queryable, for: Ecto.Associations.HasMany do
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr

  def to_query(assoc) do
    target = assoc.__ecto__(:target)
    name = assoc.__ecto__(:name)
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
  def reduce(assoc, acc, fun), do: Enum.reduce(assoc.to_list, acc, fun)
end
