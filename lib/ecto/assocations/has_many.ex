defrecord Ecto.Reflections.HasMany, [:field, :name, :owner, :associated, :foreign_key]

defmodule Ecto.Associations.HasMany do
  defrecordp :assoc, __MODULE__, [:reflection, :loaded, :target]

  def new(params // [], assoc(reflection: refl, target: target)) do
    fk = refl.foreign_key
    refl.associated.new([{ fk, target }] ++ params)
  end

  def to_list(assoc(loaded: nil, reflection: refl)) do
    raise Ecto.AssociationNotLoadedError,
      type: :has_many, owner: refl.owner, name: refl.name
  end

  def to_list(assoc(loaded: loaded)) do
    loaded
  end

  def __ecto__(:new) do
    assoc()
  end

  def __ecto__(:with_data, reflection, target, association) do
    assoc(association, reflection: reflection, target: target)
  end

  def __ecto__(:loaded, value, association) do
    assoc(association, loaded: value)
  end

  def __ecto__(:update_loaded, fun, assoc(loaded: loaded)) do
    assoc(loaded: fun.(loaded))
  end
end

defimpl Ecto.Queryable, for: Ecto.Associations.HasMany do
  def to_query(_), do: raise nil # TODO
end

defimpl Enumerable, for: Ecto.Associations.HasMany do
  def count(assoc), do: length(assoc.to_list)
  def member?(assoc, value), do: value in assoc.to_list
  def reduce(assoc, acc, fun), do: Enumerable.List.reduce(assoc.to_list, acc, fun)
end
