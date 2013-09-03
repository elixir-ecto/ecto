defrecord Ecto.Reflections.HasOne, [ :field, :owner, :associated,
  :foreign_key, :primary_key ]

defmodule Ecto.Associations.HasOne do
  @moduledoc """
  A has_one association.
  """

  alias Ecto.Reflections.HasOne, as: Refl

  @not_loaded :not_loaded

  # Needs to be defrecordp because we don't want pollute the module
  # with functions generated for the record
  defrecordp :assoc, __MODULE__, [:loaded, :target, :name]

  @doc """
  Creates a new record of the associated entity with the foreign key field set
  to the primary key of the parent entity.
  """
  def new(params // [], assoc(target: target, name: name)) do
    refl = Refl[] = elem(target, 0).__ecto__(:association, name)
    fk = refl.foreign_key
    pk_value = apply(target, refl.primary_key, [])
    refl.associated.new([{ fk, pk_value }] ++ params)
  end

  @doc """
  Returns the associated record. Raises `AssociationNotLoadedError` if the
  association was not loaded.
  """
  def get(assoc(loaded: @not_loaded, target: target, name: name)) do
    refl = elem(target, 0).__ecto__(:association, name)
    raise Ecto.AssociationNotLoadedError,
      type: :has_one, owner: refl.owner, name: name
  end

  def get(assoc(loaded: loaded)) do
    loaded
  end

  @doc false
  Enum.each [:loaded, :target, :name], fn field ->
    def __ecto__(unquote(field), record) do
      assoc(record, unquote(field))
    end

    def __ecto__(unquote(field), value, record) do
      assoc(record, [{ unquote(field), value }])
    end
  end

  def __ecto__(:new, name) do
    assoc(name: name, loaded: @not_loaded)
  end
end
