defmodule Ecto.Associations do
  @moduledoc false

  alias Ecto.Reflections.HasOne
  alias Ecto.Reflections.HasMany
  alias Ecto.Reflections.BelongsTo

  def create_reflection(type, name, module, pk, assoc, fk)
      when type in [:has_many, :has_one] do
    model_name = module |> Module.split |> List.last |> String.downcase

    values = [
      owner: module,
      associated: assoc,
      key: pk,
      assoc_key: fk || :"#{model_name}_#{pk}",
      field: name ]

    case type do
      :has_many -> struct(HasMany, values)
      :has_one  -> struct(HasOne, values)
    end
  end

  def create_reflection(:belongs_to, name, module, pk, assoc, fk) do
    %BelongsTo{
      owner: module,
      associated: assoc,
      key: fk,
      assoc_key: pk,
      field: name }
  end

  def load(struct, field, loaded) do
    Map.update!(struct, field, &(&1.__assoc__(:loaded, loaded)))
  end

  defmacro defproxy(struct) do
    quote do
      defmacrop proxy() do
        tag    = __MODULE__
        struct = unquote(struct)
        quote do
          {unquote(tag), %unquote(struct){}}
        end
      end

      defmacrop proxy(kw) do
        tag    = __MODULE__
        struct = unquote(struct)
        quote do
          {unquote(tag), %unquote(struct){unquote_splicing(kw)}}
        end
      end

      defmacrop proxy(proxy, kw) do
        tag    = __MODULE__
        struct = unquote(struct)
        quote do
          {unquote(tag), %unquote(struct){} = map} = unquote(proxy)
          {unquote(tag), %{map | unquote_splicing(kw)}}
        end
      end
    end
  end
end
