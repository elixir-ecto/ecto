defmodule Ecto.Adapter.Stage do
  @moduledoc """
  Specifies the adapter `GenStage` API.
  """

  @type flat_map :: ({integer, list | nil} -> list)
  @type insert_all :: (list -> integer)
  @type options :: Keyword.t

  @doc """
  Starts and links to a `GenStage` producer.

  The producer executes a query and returns the result to consumer(s).

  See `Ecto.Repo.start_producer/2`.
  """
  @callback start_producer(repo :: Ecto.Repo.t, Ecto.Adapter.query_meta, query, params :: list(), Ecto.Adapter.process | nil, flat_map, options) ::
            GenServer.on_start when
              query: {:nocache, Ecto.Adapter.prepared} |
                     {:cached, (Ecto.Adapter.prepared -> :ok), Ecto.Adapter.cached} |
                     {:cache, (Ecto.Adapter.cached -> :ok), Ecto.Adapter.prepared}

  @doc """
  Starts and links to a `GenStage` consumer.

  The consumers inserts the entries it receives for the schema.

  See `Ecto.Repo.start_consumer/2`
  """
  @callback start_consumer(repo :: Ecto.Repo.t, insert_all, options) ::
            GenServer.on_start
end
