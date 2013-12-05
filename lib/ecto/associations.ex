defmodule Ecto.Associations do
  @moduledoc false

  alias Ecto.Reflections.HasOne
  alias Ecto.Reflections.HasMany
  alias Ecto.Reflections.BelongsTo

  def create_reflection(type, name, model, module, pk, assoc, fk)
      when type in [:has_many, :has_one] do
    if model do
      model_name = model |> Module.split |> List.last |> String.downcase
    end

    values = [
      owner: module,
      associated: assoc,
      key: pk,
      assoc_key: fk || :"#{model_name}_#{pk}",
      field: :"__#{name}__" ]

    case type do
      :has_many -> HasMany.new(values)
      :has_one  -> HasOne.new(values)
    end
  end

  def create_reflection(:belongs_to, name, _model, module, pk, assoc, fk) do
    values = [
      owner: module,
      associated: assoc,
      key: fk,
      assoc_key: pk,
      field: :"__#{name}__" ]
    BelongsTo.new(values)
  end

  def set_loaded(record, refl, loaded) do
    if not is_record(refl, HasMany), do: loaded = Enum.first(loaded)
    field = refl.field
    association = apply(record, field, [])
    association = association.__assoc__(:loaded, loaded)
    apply(record, field, [association])
  end
end
