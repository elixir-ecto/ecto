defmodule Ecto.Adapter.Queryable do
  @moduledoc """
  Specifies the query API required from adapters.
  """

  @typedoc "Proxy type to the adapter meta"
  @type adapter_meta :: Ecto.Adapter.adapter_meta()

  @typedoc "Ecto.Query metadata fields (stored in cache)"
  @type query_meta :: %{sources: tuple, preloads: term, select: map}

  @typedoc "Cache query metadata"
  @type query_cache :: {:nocache, prepared}
                       | {:cache, (cached -> :ok), prepared}
                       | {:cached, (cached -> :ok), (prepared -> :ok), cached}

  @type prepared :: term
  @type cached :: term
  @type options :: Keyword.t()

  @doc """
  Commands invoked to prepare a query for `all`, `update_all` and `delete_all`.

  The returned result is given to `execute/6`.
  """
  @callback prepare(atom :: :all | :update_all | :delete_all, query :: Ecto.Query.t()) ::
              {:cache, prepared} | {:nocache, prepared}

  @doc """
  Executes a previously prepared query.

  It must return a tuple containing the number of entries and
  the result set as a list of lists. The result set may also be
  `nil` if a particular operation does not support them.

  The `adapter_meta` field is a map containing some of the fields found
  in the `Ecto.Query` struct.
  """
  @callback execute(adapter_meta, query_meta, query_cache, params :: list(), options) ::
              {integer, [[term]] | nil}

  @doc """
  Streams a previously prepared query.

  It returns a stream of values.

  The `adapter_meta` field is a map containing some of the fields found
  in the `Ecto.Query` struct.
  """
  @callback stream(adapter_meta, query_meta, query_cache, params :: list(), options) ::
              Enumerable.t

  @doc """
  Plans and prepares a query for the given repo, leveraging its query cache.

  This operation uses the query cache if one is available.
  """
  def prepare_query(operation, repo_name_or_pid, queryable) do
    {adapter, %{cache: cache}} = Ecto.Repo.Registry.lookup(repo_name_or_pid)

    {_meta, prepared, params} =
      queryable
      |> Ecto.Queryable.to_query()
      |> Ecto.Query.Planner.ensure_select(operation == :all)
      |> Ecto.Query.Planner.query(operation, cache, adapter, 0)

    {prepared, params}
  end

  @doc """
  Plans a query using the given adapter.

  This does not expect the repository and therefore does not leverage the cache.
  """
  def plan_query(operation, adapter, queryable) do
    query = Ecto.Queryable.to_query(queryable)
    {query, params, _key} = Ecto.Query.Planner.plan(query, operation, adapter, 0)
    {query, _} = Ecto.Query.Planner.normalize(query, operation, adapter, 0)
    {query, params}
  end
end
