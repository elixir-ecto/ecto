defmodule Ecto.DynamicRepo do
  @moduledoc """
  """

  use DynamicSupervisor

  def __sql__() do
    Ecto.Adapters.Postgres.Connection
  end

  def __adapter__() do
    Ecto.Adapters.Postgres
  end

  def __log__(_entry) do
    # Enum.reduce(opts[:loggers] || config[:loggers] || [Ecto.LogEntry], quote(do: entry), fn
    #   mod, acc when is_atom(mod) ->
    #     quote do: unquote(mod).log(unquote(acc))
    #   {Ecto.LogEntry, :log, [level]}, _acc when not(level in [:error, :info, :warn, :debug]) ->
    #     raise ArgumentError, "the log level #{inspect level} is not supported in Ecto.LogEntry"
    #   {mod, fun, args}, acc ->
    #     quote do: unquote(mod).unquote(fun)(unquote(acc), unquote_splicing(args))
    # end)
  end

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, [], name: name)
  end

  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def stop(pid, timeout \\ 5000) do
    Supervisor.stop(pid, :normal, timeout)
  end


  def start_child(repo, adapter, config) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Ecto.DynamicRepo.ChildSupervisor, {repo, adapter, config}})
  end

  def all(repo, adapter, queryable, opts \\ []) do
    Ecto.Repo.Queryable.all(repo, adapter, queryable, opts)
  end

  # @doc """
  # Returns the adapter tied to the repository.
  # """
  # @callback __adapter__ :: Ecto.Adapter.t

  # @doc """
  # A callback invoked by adapters that logs the given action.

  # See `Ecto.LogEntry` for more information and `Ecto.Repo` module
  # documentation on setting up your own loggers.
  # """
  # @callback __log__(entry :: Ecto.LogEntry.t) :: Ecto.LogEntry.t

  # @doc """
  # Returns the adapter configuration stored in the `:otp_app` environment.

  # If the `c:init/2` callback is implemented in the repository,
  # it will be invoked with the first argument set to `:dry_run`.
  # """
  # @callback config() :: Keyword.t

  # @doc """
  # Starts any connection pooling or supervision and return `{:ok, pid}`
  # or just `:ok` if nothing needs to be done.

  # Returns `{:error, {:already_started, pid}}` if the repo is already
  # started or `{:error, term}` in case anything else goes wrong.

  # ## Options

  # See the configuration in the moduledoc for options shared between adapters,
  # for adapter-specific configuration see the adapter's documentation.
  # """
  # @callback start_link(opts :: Keyword.t) :: {:ok, pid} |
  #                           {:error, {:already_started, pid}} |
  #                           {:error, term}

  # @doc """
  # A callback executed when the repo starts or when configuration is read.

  # The first argument is the context the callback is being invoked. If it
  # is called because the Repo supervisor is starting, it will be `:supervisor`.
  # It will be `:dry_run` if it is called for reading configuration without
  # actually starting a process.

  # The second argument is the repository configuration as stored in the
  # application environment. It must return `{:ok, keyword}` with the updated
  # list of configuration or `:ignore` (only in the `:supervisor` case).
  # """
  # @callback init(:supervisor | :dry_run, config :: Keyword.t) :: {:ok, Keyword.t} | :ignore

  # @doc """
  # Shuts down the repository represented by the given pid.
  # """
  # @callback stop(pid, timeout) :: :ok

  # @doc """
  # Fetches all entries from the data store matching the given query.

  # May raise `Ecto.QueryError` if query validation fails.

  # ## Options

  #   * `:prefix` - The prefix to run the query on (such as the schema path
  #     in Postgres or the database in MySQL). This overrides the prefix set
  #     in the query.

  # See the "Shared options" section at the module documentation.

  # ## Example

  #     # Fetch all post titles
  #     query = from p in Post,
  #          select: p.title
  #     MyRepo.all(query)
  # """
  # @callback all(repo :: pid | atom, queryable :: Ecto.Query.t, opts :: Keyword.t) :: [Ecto.Schema.t] | no_return
end
