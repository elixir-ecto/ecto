defmodule Ecto.Embedded do
  @moduledoc """
  The embedding struct for `embeds_one` and `embeds_many`.

  Its fields are:

  * `cardinality` - The association cardinality
  * `field` - The name of the association field on the model
  * `owner` - The model where the association was defined
  * `embedded` - The model that is embedded
  """

  defstruct [:cardinality, :field, :owner, :embed, :container, :changeset]

  @doc """
  Builds the embedded struct.

  ## Options

    * `:cardinality` - tells if there is one embedded model or many
    * `:field` - tells the field in the owner struct where the
      embeds should be stored
    * `:owner` - the owner module of the embedding
    * `:owner_key` - the key in the owner with the association value
    * `:changeset` - the changeset function

  """
  def struct(module, name, opts) do
    %__MODULE__{
      field: name,
      cardinality: Keyword.fetch!(opts, :cardinality),
      owner: module,
      embed: Keyword.fetch!(opts, :embed),
      container: Keyword.get(opts, :container),
      changeset: Keyword.fetch!(opts, :changeset)
    }
  end
end
