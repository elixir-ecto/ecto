defrecord Ecto.Reflections.HasMany, [:field, :owner, :associated, :key, :assoc_key] do
  @moduledoc """
  The reflection record for a `has_many` association. Its fields are:

  * `field` - The name of the association field on the entity;
  * `owner` - The model where the association was defined;
  * `associated` - The model that is associated;
  * `key` - The key on the `owner` model used for the association;
  * `assoc_key` - The key on the `associated` model used for the association;
  """
end

defmodule Ecto.Associations.HasMany do
  @moduledoc """
  A has_many association.

  ## Reflection

  Any association module will generate the `__assoc__` function that can be
  used for runtime introspection of the association.

  * `__assoc__(:loaded, assoc)` - Returns the loaded entities or `:not_loaded`;
  * `__assoc__(:loaded, value, assoc)` - Sets the loaded entities;
  * `__assoc__(:target, assoc)` - Returns the entity where the association was
                                  defined;
  * `__assoc__(:name, assoc)` - Returns the name of the association field on the
                                entity;
  * `__assoc__(:primary_key, assoc)` - Returns the primary key (used when
                                       creating a an entity with `new/2`);
  * `__assoc__(:primary_key, value, assoc)` - Sets the primary key;
  * `__assoc__(:new, name, target)` - Creates a new association with the given
                                      name and target;
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
      assoc([{ unquote(field), var }]) = record
      var
    end
  end

  @doc false
  Enum.each [:loaded, :primary_key], fn field ->
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
  def reduce(assoc, acc, fun), do: Enumerable.List.reduce(assoc.to_list, acc, fun)
end

defimpl Inspect, for: Ecto.Associations.HasMany do
  import Inspect.Algebra

  def inspect(assoc, opts) do
    name        = assoc.__assoc__(:name)
    target      = assoc.__assoc__(:target)
    refl        = target.__entity__(:association, name)
    associated  = refl.associated
    references  = refl.key
    foreign_key = refl.assoc_key
    kw = [
      name: name,
      target: target,
      associated: associated,
      references: references,
      foreign_key: foreign_key
    ]
    concat ["#Ecto.Associations.HasMany<", Kernel.inspect(kw, opts), ">"]
  end
end
