defmodule Ecto.Schema.Metadata do
  @moduledoc """
  Stores metadata of a struct.

  ## State

  The state of the schema is stored in the `:state` field and allows
  following values:

    * `:built` - the struct was constructed in memory and is not persisted
      to database yet;
    * `:loaded` - the struct was loaded from database and represents
      persisted data;
    * `:deleted` - the struct was deleted and no longer represents persisted
      data.

  ## Source

  The `:source` tracks the (table or collection) where the struct is or should
  be persisted to.

  ## Prefix

  Tracks the source prefix in the data storage.

  ## Context

  The `:context` field represents additional state some databases require
  for proper updates of data. It is not used by the built-in adapters of
  `Ecto.Adapters.Postres` and `Ecto.Adapters.MySQL`.

  ## Schema

  The `:schema` field refers the module name for the schema this metadata belongs to.
  """
  defstruct [:state, :source, :context, :schema, :prefix]

  @type state :: :built | :loaded | :deleted

  @type t :: %__MODULE__{
          context: any,
          prefix: Ecto.Schema.prefix(),
          schema: module,
          source: Ecto.Schema.source(),
          state: state
        }

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(metadata, opts) do
      %{source: source, prefix: prefix, state: state, context: context} = metadata

      entries =
        for entry <- [state, prefix, source, context],
            entry != nil,
            do: to_doc(entry, opts)

      concat(["#Ecto.Schema.Metadata<"] ++ Enum.intersperse(entries, ", ") ++ [">"])
    end
  end
end
