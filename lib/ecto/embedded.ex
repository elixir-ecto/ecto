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

  @doc """
  Normalizes the changeset function

  The new_fun can have formats as the changeset field. Returns the struct
  with the changeset field updated to have a changeset fun, that can be
  called with params.
  """
  def normalize_changeset(%__MODULE__{embed: module} = embed, new_fun) do
    update_in embed.changeset, &do_normalize_changeset(&1, module, new_fun)
  end

  defp do_normalize_changeset({mod, fun}, _module, nil),
    do: &apply(mod, fun, &1)
  defp do_normalize_changeset(fun, _module, nil) when is_function(fun),
    do: fun
  defp do_normalize_changeset(fun, module, nil),
    do: &apply(module, fun, &1)
  defp do_normalize_changeset(_fun, _module, {mod, fun}),
    do: &apply(mod, fun, &1)
  defp do_normalize_changeset(_fun, _module, fun) when is_function(fun),
    do: fun
  defp do_normalize_changeset(_fun, module, fun),
    do: &apply(module, fun, &1)
end
