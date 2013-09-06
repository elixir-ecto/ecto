defrecord Ecto.Reflections.HasMany, [ :field, :owner, :associated,
  :foreign_key, :primary_key ]

defmodule Ecto.Associations.HasMany do
  @moduledoc """
  A has_many association.
  """

  alias Ecto.Reflections.HasMany, as: Refl

  @not_loaded :not_loaded

  # Needs to be defrecordp because we don't want pollute the module
  # with functions generated for the record
  defrecordp :assoc, __MODULE__, [:loaded, :target, :name, :primary_key]

  @doc """
  Creates a new record of the associated entity with the foreign key field set
  to the primary key of the parent entity.
  """
  def new(params // [], assoc(target: target, name: name)) do
    refl = Refl[] = target.__ecto__(:association, name)
    fk = refl.foreign_key
    pk_value = apply(target, refl.primary_key, [])
    refl.associated.new([{ fk, pk_value }] ++ params)
  end

  @doc """
  Returns a list of the associated records. Raises `AssociationNotLoadedError`
  if the association was not loaded.
  """
  def to_list(assoc(loaded: @not_loaded, target: target, name: name)) do
    refl = target.__ecto__(:association, name)
    raise Ecto.AssociationNotLoadedError,
      type: :has_many, owner: refl.owner, name: name
  end

  def to_list(assoc(loaded: loaded)) do
    loaded
  end

  @doc false
  Enum.each [:loaded, :target, :name, :primary_key], fn field ->
    def __ecto__(unquote(field), record) do
      assoc(record, unquote(field))
    end

    def __ecto__(unquote(field), value, record) do
      assoc(record, [{ unquote(field), value }])
    end
  end

  def __ecto__(:new, name, target) do
    assoc(name: name, target: target, loaded: @not_loaded)
  end
end

defimpl Ecto.Queryable, for: Ecto.Associations.HasMany do
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Associations.HasMany

  def to_query(assoc) do
    target   = assoc.__ecto__(:target)
    name     = assoc.__ecto__(:name)
    pk_value = assoc.__ecto__(:primary_key)
    refl     = target.__ecto__(:association, name)
    fk       = refl.foreign_key
    from     = refl.associated

    if nil?(pk_value) do
      raise ArgumentError, "cannot create query when the association's primary " <>
        "key is not set on the entity"
      end
    end

    where_expr = quote do &0.unquote(fk) == unquote(pk_value) end
    where = QueryExpr[expr: where_expr]
    Query[from: from, wheres: [where]]
  end
end

defimpl Enumerable, for: Ecto.Associations.HasMany do
  def count(assoc), do: length(assoc.to_list)
  def member?(assoc, value), do: value in assoc.to_list
  def reduce(assoc, acc, fun), do: Enum.reduce(assoc.to_list, acc, fun)
end
