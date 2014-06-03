defmodule Ecto.Model do
  @moduledoc """
  Models are Elixir modules with Ecto-specific behaviour.

  This module is an "umbrella" module that adds a bunch of functionality
  to your module:

  * `Ecto.Model.Schema` - provides the API necessary to define schemas;
  * `Ecto.Model.Callbacks` - to be implemented;
  * `Ecto.Model.Validations` - helpers for validations;

  By using `Ecto.Model` all the functionality above is included,
  but you can cherry pick the ones you want to use.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Ecto.Model.Schema
      use Ecto.Model.Validations
    end
  end

  @type t :: map

  @key_assocs [Ecto.Reflections.HasOne, Ecto.Reflections.HasMany]

  @doc """
  Returns the model's primary key.

  Raises `Ecto.NoPrimaryKey` if model has no primary key.
  """
  @spec primary_key(t) :: any
  def primary_key(%{__struct__: module} = model) do
    if pk_field = module.__schema__(:primary_key) do
      Map.get(model, pk_field)
    else
      raise Ecto.NoPrimaryKey, model: model
    end
  end

  @doc """
  Sets the model's primary key.

  Raises `Ecto.NoPrimaryKey` if model has no primary key.
  """
  @spec put_primary_key(t, any) :: t
  def put_primary_key(%{__struct__: module} = model, id) do
    unless pk_field = module.__schema__(:primary_key) do
      raise Ecto.NoPrimaryKey, model: model
    end

    fields = module.__schema__(:associations)

    model = Map.put(model, pk_field, id)

    Enum.reduce(fields, model, fn field, model ->
      if (refl = module.__schema__(:association, field)) && refl.__struct__ in @key_assocs do
        Map.update!(model, refl.field, &(&1.__assoc__(:primary_key, id)))
      else
        model
      end
    end)
  end

  @doc """
  Scopes a query to the local model.

  Shorthand for `from(var in __MODULE__, ...)`.
  """
  defmacro scoped(field, opts) do
    quote do
      from unquote(field) in __MODULE__, unquote(opts)
    end
  end
end

