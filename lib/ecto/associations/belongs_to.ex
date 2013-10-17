defrecord Ecto.Reflections.BelongsTo, [ :field, :owner, :associated,
  :foreign_key, :primary_key ]

defmodule Ecto.Associations.BelongsTo do
  @moduledoc """
  A belongs_to association.
  """

  @not_loaded :not_loaded

  # Needs to be defrecordp because we don't want pollute the module
  # with functions generated for the record
  defrecordp :assoc, __MODULE__, [:loaded, :target, :name]

  @doc """
  Creates a new record of the associated entity.
  """
  def new(params // [], assoc(target: target, name: name)) do
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

defimpl Inspect, for: Ecto.Associations.BelongsTo do
  import Inspect.Algebra

  def inspect(assoc, opts) do
    name        = assoc.__assoc__(:name)
    target      = assoc.__assoc__(:target)
    refl        = target.__entity__(:association, name)
    associated  = refl.associated
    primary_key = refl.primary_key
    foreign_key = refl.foreign_key
    kw = [
      name: name,
      target: target,
      associated: associated,
      primary_key: primary_key,
      foreign_key: foreign_key
    ]
    concat ["#Ecto.Associations.BelongsTo<", Kernel.inspect(kw, opts), ">"]
  end
end
