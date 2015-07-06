defmodule Ecto.Embedded do
  @moduledoc """
  The embedding struct for `embeds_one` and `embeds_many`.

  Its fields are:

  * `cardinality` - The association cardinality
  * `field` - The name of the association field on the model
  * `owner` - The model where the association was defined
  * `embedded` - The model that is embedded
  """

  defstruct [:cardinality, :field, :owner, :embedded]

  @doc """
  Builds the embedded struct.

  ## Options

    * `:cardinality` - tells if there is one embedded model or many
    * `:field` - tells the field in the owner struct where the
      embeds should be stored
    * `:owner` - the owner module of the embedding
    * `:owner_key` - the key in the owner with the association value

  """
  def struct(module, name, opts) do
    %__MODULE__{
      field: name,
      cardinality: Keyword.fetch!(opts, :cardinality),
      owner: module,
      embedded: Keyword.fetch!(opts, :embedded),
    }
  end


  @doc """
  Builds a model for the given embedding.

  The struct to build from is given as argument in case default values
  should be set in the struct.

  Invoked by `Ecto.Model.build_embedded/3`.
  """
  def build(%{embedded: embedded}, _struct, attributes) do
    embedded
    |> struct(attributes)
  end

  @doc """
  Retrieves the association from the given model.
  """
  def embedded_from_model!(model, embed) do
    model.__schema__(:embed, embed) ||
      raise ArgumentError,
        "model #{inspect model} does not have embedded #{inspect embed}"
  end
end
