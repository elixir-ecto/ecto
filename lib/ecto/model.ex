defmodule Ecto.Model do
  @moduledoc """
  Warning: this module is currently deprecated. Instead
  `use Ecto.Schema` and the functions in the `Ecto` module.

  `Ecto.Model` is built on top of `Ecto.Schema`. See
  `Ecto.Schema` for documentation on the `schema/2` macro,
  as well which fields, associations, types are available.

  ## Using

  When used, `Ecto.Model` imports itself. All the modules
  existing in `Ecto.Model.*` are brought in too:

    * `use Ecto.Model.Callbacks` - provides lifecycle callbacks
    * `use Ecto.Model.OptimisticLock` - makes the `optimistic_lock/1` macro
      available

  However, you can avoid using `Ecto.Model` altogether in favor
  of cherry-picking any of the functionality above.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Model

      use Ecto.Model.OptimisticLock
      use Ecto.Model.Callbacks
    end
  end

  @type t :: %{__struct__: atom}

  @doc false
  def primary_key(struct) do
    Ecto.primary_key(struct)
  end

  @doc false
  def primary_key!(struct) do
    Ecto.primary_key!(struct)
  end

  @doc false
  def build(struct, assoc, attributes \\ %{}) do
    Ecto.build_assoc(struct, assoc, attributes)
  end

  @doc false
  def assoc(model_or_models, assoc) do
    Ecto.assoc(model_or_models, assoc)
  end

  @doc false
  def put_source(model, new_source, new_prefix \\ nil) do
    IO.puts :stderr, "warning: Ecto.Model.put_source/3 is deprecated in favor of " <>
                     "Ecto.Model.put_meta/2\n#{Exception.format_stacktrace}"
    put_in model.__meta__.source, {new_prefix, new_source}
  end
end
