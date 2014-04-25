defrecord Ecto.Reflections.BelongsTo, [:field, :owner, :associated, :key, :assoc_key] do
  @moduledoc """
  The reflection record for a `belongs_to` association. Its fields are:

  * `field` - The name of the association field on the entity;
  * `owner` - The model where the association was defined;
  * `associated` - The model that is associated;
  * `key` - The key on the `owner` model used for the association;
  * `assoc_key` - The key on the `associated` model used for the association;
  """
end

defmodule Ecto.Associations.BelongsTo do
  @moduledoc """
  A belongs_to association.

  ## Reflection

  Any association module will generate the `__assoc__` function that can be
  used for runtime introspection of the association.

  * `__assoc__(:loaded, assoc)` - Returns the loaded entities or `:not_loaded`;
  * `__assoc__(:loaded, value, assoc)` - Sets the loaded entities;
  * `__assoc__(:target, assoc)` - Returns the entity where the association was
                                  defined;
  * `__assoc__(:name, assoc)` - Returns the name of the association field on the
                                entity;
  * `__assoc__(:new, name, target)` - Creates a new association with the given
                                      name and target;
  """

  @not_loaded :not_loaded

  # Needs to be defrecordp because we don't want to pollute the module
  # with functions generated for the record
  defrecordp :assoc, __MODULE__, [:loaded, :target, :name]

  @doc """
  Creates a new record of the associated entity.
  """
  def new(params \\ [], assoc(target: target, name: name)) do
    refl = target.__entity__(:association, name)
    refl.associated.new(params)
  end

  @doc """
  Returns the associated record. Raises `AssociationNotLoadedError` if the
  association is not loaded.
  """
  def get(assoc(loaded: @not_loaded, target: target, name: name)) do
    refl = target.__entity__(:association, name)
    raise Ecto.AssociationNotLoadedError,
      type: :belongs_to, owner: refl.owner, name: name
  end

  def get(assoc(loaded: loaded)) do
    loaded
  end

  @doc """
  Returns `true` if the association is loaded.
  """
  def loaded?(assoc(loaded: @not_loaded)), do: false
  def loaded?(_), do: true

  @doc false
  Enum.each [:loaded, :target, :name], fn field ->
    def __assoc__(unquote(field), record) do
      assoc([{ unquote(field), var }]) = record
      var
    end
  end

  @doc false
  def __assoc__(:loaded, value, record) do
    assoc(record, [loaded: value])
  end

  def __assoc__(:new, name, target) do
    assoc(name: name, target: target, loaded: @not_loaded)
  end
end

defimpl Inspect, for: Ecto.Associations.BelongsTo do
  import Inspect.Algebra

  def inspect(assoc, opts) do
    name        = assoc.__assoc__(:name)
    target      = assoc.__assoc__(:target)
    refl        = target.__entity__(:association, name)
    associated  = refl.associated
    foreign_key = refl.key
    references  = refl.assoc_key
    kw = [
      name: name,
      target: target,
      associated: associated,
      references: references,
      foreign_key: foreign_key
    ]
    concat ["#Ecto.Associations.BelongsTo<", Kernel.inspect(kw, opts), ">"]
  end
end
