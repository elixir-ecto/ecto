defrecord Ecto.Reflections.HasMany, [ :field, :owner, :associated,
  :key, :assoc_key ]

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
  def new(params // [], assoc(target: target, name: name, primary_key: pk_value)) do
    refl = Refl[] = target.__entity__(:association, name)
    fk = refl.assoc_key
    refl.associated.new([{ fk, pk_value }] ++ params)
  end

  @doc """
  Returns a list of the associated records. Raises `AssociationNotLoadedError`
  if the association is not loaded.
  """
  def to_list(assoc(loaded: @not_loaded, target: target, name: name)) do
    refl = target.__entity__(:association, name)
    raise Ecto.AssociationNotLoadedError,
      type: :has_many, owner: refl.owner, name: name
  end

  def to_list(assoc(loaded: loaded)) do
    loaded
  end

  @doc """
  Returns `true` if the association is loaded.
  """
  def loaded?(assoc(loaded: @not_loaded)), do: false
  def loaded?(_), do: true

  @doc false
  Enum.each [:loaded, :target, :name, :primary_key], fn field ->
    def __assoc__(unquote(field), record) do
      assoc(record, unquote(field))
    end

    def __assoc__(unquote(field), value, record) do
      assoc(record, [{ unquote(field), value }])
    end
  end

  def __assoc__(:new, name, target) do
    assoc(name: name, target: target, loaded: @not_loaded)
  end
end

defimpl Ecto.Queryable, for: Ecto.Associations.HasMany do
  require Ecto.Query, as: Q

  def to_query(assoc) do
    target   = assoc.__assoc__(:target)
    name     = assoc.__assoc__(:name)
    pk_value = assoc.__assoc__(:primary_key)
    refl     = target.__entity__(:association, name)

    Q.from x in refl.associated,
    where: field(x, ^refl.assoc_key) == ^pk_value
  end
end

defimpl Enumerable, for: Ecto.Associations.HasMany do
  def count(assoc), do: length(assoc.to_list)
  def member?(assoc, value), do: value in assoc.to_list
  def reduce(assoc, acc, fun), do: Enum.reduce(assoc.to_list, acc, fun)
end

defimpl Inspect, for: Ecto.Associations.HasMany do
  import Inspect.Algebra

  def inspect(assoc, opts) do
    name        = assoc.__assoc__(:name)
    target      = assoc.__assoc__(:target)
    refl        = target.__entity__(:association, name)
    associated  = refl.associated
    primary_key = refl.key
    foreign_key = refl.assoc_key
    kw = [
      name: name,
      target: target,
      associated: associated,
      primary_key: primary_key,
      foreign_key: foreign_key
    ]
    concat ["#Ecto.Associations.HasMany<", Kernel.inspect(kw, opts), ">"]
  end
end
