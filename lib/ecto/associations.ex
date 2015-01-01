defmodule Ecto.Associations do
  @moduledoc false
  # TODO: Document which association fields are required
  # TODO: Document the associations behaviour

  @doc """
  Returns the association key for the given module with the given prefix.

  ## Examples

      iex> association_key(Hello.World, :id)
      :world_id

      iex> association_key(Hello.HTTP, :id)
      :http_id

      iex> association_key(Hello.HTTPServer, :id)
      :http_server_id

  """
  def association_key(module, suffix) do
    prefix = module |> Module.split |> List.last |> underscore
    :"#{prefix}_#{suffix}"
  end

  def underscore(""), do: ""

  def underscore(<<h, t :: binary>>) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<h, t, rest :: binary>>, _) when h in ?A..?Z and not t in ?A..?Z do
    <<?_, to_lower_char(h), t>> <> do_underscore(rest, t)
  end

  defp do_underscore(<<h, t :: binary>>, prev) when h in ?A..?Z and not prev in ?A..?Z do
    <<?_, to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<?-, t :: binary>>, _) do
    <<?_>> <> do_underscore(t, ?-)
  end

  defp do_underscore(<< "..", t :: binary>>, _) do
    <<"..">> <> underscore(t)
  end

  defp do_underscore(<<?.>>, _), do: <<?.>>

  defp do_underscore(<<?., t :: binary>>, _) do
    <<?/>> <> underscore(t)
  end

  defp do_underscore(<<h, t :: binary>>, _) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<>>, _) do
    <<>>
  end

  defp to_lower_char(char) when char in ?A..?Z, do: char + 32
  defp to_lower_char(char), do: char
end

defmodule Ecto.Associations.NotLoaded do
  @moduledoc """
  Struct returned by one to one associations when there are not loaded.

  The fields are:

    * `:__field__` - the association field in `__owner__`
    * `:__owner__` - the model that owns the association

  """
  defstruct [:__field__, :__owner__]

  defimpl Inspect do
    def inspect(not_loaded, _opts) do
      msg = "association #{inspect not_loaded.__field__} is not loaded"
      ~s(#Ecto.Associations.NotLoaded<#{msg}>)
    end
  end
end

defmodule Ecto.Associations.Has do
  @moduledoc """
  The reflection record for a `has_one` and `has_many` associations.
  Its fields are:

  * `cardinality` - The association cardinality
  * `field` - The name of the association field on the model
  * `owner` - The model where the association was defined
  * `assoc` - The model that is associated
  * `owner_key` - The key on the `owner` model used for the association
  * `assoc_key` - The key on the `associated` model used for the association
  """

  defstruct [:cardinality, :field, :owner, :assoc, :owner_key, :assoc_key]

  @doc false
  def struct(name, module, primary_key, fields, opts) do
    ref = opts[:references] || primary_key

    if is_nil(ref) do
      raise ArgumentError, "need to set :references option for " <>
        "association #{inspect name} when model has no primary key"
    end

    unless ref in fields do
      raise ArgumentError, "model does not have the field #{inspect ref} used by " <>
        "association #{inspect name}, please set the :references option accordingly"
    end

    %__MODULE__{
      field: name,
      cardinality: Keyword.fetch!(opts, :cardinality),
      owner: module,
      assoc: Keyword.fetch!(opts, :queryable),
      owner_key: ref,
      assoc_key: opts[:foreign_key] || Ecto.Associations.association_key(module, ref)
    }
  end
end

defmodule Ecto.Associations.BelongsTo do
  @moduledoc """
  The reflection struct for a `belongs_to` association. Its fields are:

  * `cardinality` - The association cardinality
  * `field` - The name of the association field on the model
  * `owner` - The model where the association was defined
  * `assoc` - The model that is associated
  * `owner_key` - The key on the `owner` model used for the association;
  * `assoc_key` - The key on the `assoc` model used for the association
  """

  defstruct [:cardinality, :field, :owner, :assoc, :owner_key, :assoc_key]

  @doc false
  def struct(name, module, primary_key, _fields, opts) do
    ref = opts[:references] || primary_key

    if is_nil(ref) do
      raise ArgumentError, "need to set :references option for " <>
        "association #{inspect name} when model has no primary key"
    end

    %__MODULE__{
      field: name,
      cardinality: :one,
      owner: module,
      assoc: Keyword.fetch!(opts, :queryable),
      owner_key: Keyword.fetch!(opts, :foreign_key),
      assoc_key: ref
    }
  end
end
