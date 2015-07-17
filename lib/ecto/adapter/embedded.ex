defmodule Ecto.Adapter.Embedded do
  @doc """
  Specifies the API for adapters to support embedded models
  """

  use Behaviour

  @doc """
  Performs dumping of the embedded model.

  The value returned will be later passed to the adapter on insert and update.
  All nested embeds should be returned unchanged - they will be recursively,
  dumped using this function.
  """
  defcallback dump_embed(Ecto.Model.t, atom, %{atom => Ecto.Type.t}, Ecto.Adapter.id_types) :: map

  @doc """
  Performs loading of the data in the embedded model.

  The model itself is loaded at a later stage.

  All nested embeds should be returned unchanged - they will be recursively,
  loaded using this function.
  """
  defcallback load_embed(map, atom, %{atom => Ecto.Type.t}, Ecto.Adapter.id_types) :: map
end
