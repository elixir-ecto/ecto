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
      foreign_key: fk || :"#{model_name}_#{pk}",
      primary_key: pk,
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
      foreign_key: fk,
      primary_key: pk,
      field: :"__#{name}__" ]
    BelongsTo.new(values)
  end
end
