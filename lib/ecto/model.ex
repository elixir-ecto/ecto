defmodule Ecto.Model do
  @moduledoc """
  Warning: this module is currently deprecated. Instead
  `use Ecto.Schema` and the functions in the `Ecto` module.
  """

  @doc false
  defmacro __using__(_opts) do
    IO.write :stderr, "warning: using Ecto.Model is deprecated, please use Ecto.Schema instead\n" <>
                      Exception.format_stacktrace(Macro.Env.stacktrace(__CALLER__))
    quote do
      use Ecto.Schema
      import Ecto.Model
      import Ecto.Changeset
      import Ecto.Query, only: [from: 2]
    end
  end

  @type t :: %{__struct__: atom}

  @doc false
  def primary_key(struct) do
    IO.write :stderr, "warning: Ecto.Model.primary_key/1 is deprecated, please use Ecto.primary_key/1 instead\n" <>
                      Exception.format_stacktrace()
    Ecto.primary_key(struct)
  end

  @doc false
  def primary_key!(struct) do
    IO.write :stderr, "warning: Ecto.Model.primary_key!/1 is deprecated, please use Ecto.primary_key!/1 instead\n" <>
                      Exception.format_stacktrace()
    Ecto.primary_key!(struct)
  end

  @doc false
  def build(struct, assoc, attributes \\ %{}) do
    IO.write :stderr, "warning: Ecto.Model.build/3 is deprecated, please use Ecto.build_assoc/3 instead\n" <>
                      Exception.format_stacktrace()
    Ecto.build_assoc(struct, assoc, attributes)
  end

  @doc false
  def assoc(model_or_models, assoc) do
    IO.write :stderr, "warning: Ecto.Model.assoc/2 is deprecated, please use Ecto.assoc/2 instead\n" <>
                      Exception.format_stacktrace()
    Ecto.assoc(model_or_models, assoc)
  end

  @doc false
  def put_source(model, new_source, new_prefix \\ nil) do
    IO.write :stderr, "warning: Ecto.Model.put_source/3 is deprecated, please use Ecto.put_meta/3 instead\n" <>
                      Exception.format_stacktrace()
    put_in model.__meta__.source, {new_prefix, new_source}
  end
end
