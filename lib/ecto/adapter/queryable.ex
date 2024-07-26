defmodule Ecto.Adapter.Queryable do
  @moduledoc """
  Specifies the query API required from adapters.

  If your adapter is only able to respond to one or a couple of the query functions,
  add custom implementations of those functions directly to the Repo
  by using `c:Ecto.Adapter.__before_compile__/1` instead.
  """

  @typedoc "Proxy type to the adapter meta"
  @type adapter_meta :: Ecto.Adapter.adapter_meta()

  @typedoc "Ecto.Query metadata fields (stored in cache)"
  @type query_meta :: %{sources: tuple, preloads: term, select: map}

  @typedoc """
  Cache query metadata that is passed to `c:execute/5`.

  The cache can be in 3 states, documented below.

  If `{:nocache, prepared}` is given, it means the query was
  not and cannot be cached. The `prepared` value is the value
  returned by `c:prepare/2`.

  If `{:cache, cache_function, prepared}` is given, it means
  the query can be cached and it must be cached by calling
  the `cache_function` function with the cache entry of your
  choice. Once `cache_function` is called, the next time the
  same query is given to `c:execute/5`, it will receive the
  `:cached` tuple.

  If `{:cached, update_function, reset_function, cached}` is
  given, it means the query has been cached. You may call
  `update_function/1` if you want to update the cached result.
  Or you may call `reset_function/1`, with a new prepared query,
  to force the query to be cached again. If `reset_function/1`
  is called, the next time the same query is given to
  `c:execute/5`, it will receive the `:cache` tuple.
  """
  @type query_cache :: {:nocache, prepared}
                       | {:cache, cache_function :: (cached -> :ok), prepared}
                       | {:cached, update_function :: (cached -> :ok), reset_function :: (prepared -> :ok), cached}

  @type prepared :: term
  @type cached :: term
  @type options :: Keyword.t()
  @type selected :: term

  @doc """
  Commands invoked to prepare a query.

  It is used on `c:Ecto.Repo.all/2`, `c:Ecto.Repo.update_all/3`,
  and `c:Ecto.Repo.delete_all/2`. It returns a tuple, indicating if
  this query can be cached or not, and the `prepared` query.
  The `prepared` query is any term that will be passed to the
  adapter's `c:execute/5`.
  """
  @callback prepare(atom :: :all | :update_all | :delete_all, query :: Ecto.Query.t()) ::
              {:cache, prepared} | {:nocache, prepared}

  @doc """
  Executes a previously prepared query.

  The `query_meta` field is a map containing some of the fields
  found in the `Ecto.Query` struct, after they have been normalized.
  For example, the values `selected` by the query, which then have
  to be returned, can be found in `query_meta`.

  The `query_cache` and its state is documented in `t:query_cache/0`.

  The `params` is the list of query parameters. For example, for
  a query such as `from Post, where: [id: ^123]`, `params` will be
  `[123]`.

  Finally, `options` is a keyword list of options given to the
  `Repo` operation that triggered the adapter call. Any option is
  allowed, as this is a mechanism to allow users of Ecto to customize
  how the adapter behaves per operation.

  It must return a tuple containing the number of entries and
  the result set as a list of lists. The entries in the actual
  list will depend on what has been selected by the query. The
  result set may also be `nil`, if no value is being selected.
  """
  @callback execute(adapter_meta, query_meta, query_cache, params :: list(), options) ::
              {non_neg_integer, [[selected]] | nil}

  @doc """
  Streams a previously prepared query.

  See `c:execute/5` for a description of arguments.

  It returns a stream of values.
  """
  @callback stream(adapter_meta, query_meta, query_cache, params :: list(), options) ::
              Enumerable.t

  @doc """
  Plans and prepares a query for the given repo, leveraging its query cache.

  This operation uses the query cache if one is available.
  """
  def prepare_query(operation, repo_name_or_pid, queryable) do
    %{adapter: adapter, cache: cache} = Ecto.Repo.Registry.lookup(repo_name_or_pid)

    {_meta, prepared, _cast_params, dump_params} =
      queryable
      |> Ecto.Queryable.to_query()
      |> Ecto.Query.Planner.ensure_select(operation == :all)
      |> Ecto.Query.Planner.query(operation, cache, adapter, 0)

    {prepared, dump_params}
  end

  @doc """
  Plans a query using the given adapter.

  This does not expect the repository and therefore does not leverage the cache.
  """
  def plan_query(operation, adapter, queryable) do
    query = Ecto.Queryable.to_query(queryable)
    {query, params, _key} = Ecto.Query.Planner.plan(query, operation, adapter)
    {cast_params, dump_params} = Enum.unzip(params)
    {query, _} = Ecto.Query.Planner.normalize(query, operation, adapter, 0)
    {query, cast_params, dump_params}
  end
end
