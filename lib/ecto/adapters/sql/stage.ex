defmodule Ecto.Adapters.SQL.Stage do
  @moduledoc """
  A `GenStage` process that encapsulates a SQL transaction.
  """

  @doc """
  Start link a `GenStage` process that will run a transaction for its duration.

  The first argument is the pool, the second argument is the `GenStage` type,
  the third argument is the start function, the fourth argument is the handle
  function, the fifth argument is the stop function and the optional sixth
  argument are the options.

  The start function is a o-arity anonymous function. This is called after the
  transaction begins but before `start_link/6` returns. It should return the
  `state` or call `MyRepo.rollback/1` to stop the `GenStage`.

  The handle function is a 2-arity anonymous function. If the `GenStage` type is
  a `:producer`, then the first argument is the `demand` from a `GenStage`
  `handle_demand` callback. Otherwise the first argument is the events from a
  `GenStage` `handle_events` callback. The second argument is the state. This
  function returns a 2-tuple, with first element as events (empty list for
  `:consumer`) and second element as the `state`. This function can roll back
  and stop the `GenStage` using `MyRepo.rollback/1`.

  The stop function is a 2-arity anonymous function. The first argument is the
  terminate reason and the second argument is the `state`. This function will
  only be called if connection is alive and the transaction has not been rolled
  back. If this function returns the transaction is committed. This function can
  roll back and stop the `GenStage` using `MyRepo.rollback/1`.

  The `GenStage` process will behave like a `Flow` stage:

    * It will stop with reason `:normal` when the last consumer cancels
    * It will notify consumers that it is done when all producers have cancelled
    or notified that they are done or halted
    * It will cancel new and remaining producers when all producers have
    notified that they are done or halted and it is a `:consumer`
    * It will not send demand to new producers when all producers have notified
    that they are done or halted and it is a `:consumer_producer`

  ### Options

    * `:name` - A name to register the started process (see the `:name` option
    in `GenServer.start_link/3`)

  See the "Shared options" section at the `Ecto.Repo` documentation. All options
  are passed to the `GenStage` on init.

  ### Example

      start = fn() -> Post end
      handle =
        fn(entries, schema) ->
          MyRepo.insert_all(schema, entries)
          {[], schema}
        end
      stop =
        fn
          :normal, _ -> :ok
          reason,  _ -> MyRepo.rollback(reason)
        end
      Ecto.Adapters.SQL.Stage.start_link(MyRepo, :consumer, start, handle, stop)
  """
  @spec start_link(repo :: module, :producer,
    start :: (() -> state),
    handle_demand :: ((demand :: pos_integer, state) -> {[any], state}),
    stop :: ((reason :: any, state) -> any), opts :: Keyword.t) ::
    GenServer.on_start when state: var
  @spec start_link(repo :: module, :producer_consumer,
    start :: (() -> state),
    handle_events :: (([any], state) -> {[any], state}),
    stop :: ((reason :: any, state) -> any), opts :: Keyword.t) ::
    GenServer.on_start when state: var
  @spec start_link(repo :: module, :consumer,
    start :: (() -> state),
    handle_events :: (([any], state) -> {[], state}),
    stop :: ((reason :: any, state) -> any), opts :: Keyword.t) ::
    GenServer.on_start when state: var
  def start_link(repo, type, start, handle, stop, opts \\ []) do
    Ecto.Adapters.SQL.stage(repo, type, start, handle, stop, opts)
  end

  @doc """
  Starts a `GenStage` producer that emits all entries from the data store
  matching the given query. SQL adapters, such as Postgres and MySQL, will use
  a separate transaction to enumerate the stream.

  May raise `Ecto.QueryError` if query validation fails.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the query

    * `:max_rows` - The number of rows to load from the database as we stream.
      It is supported at least by Postgres and MySQL and defaults to 500.

  See the "Shared options" section at the `Ecto.Repo` documentation.

  ## Example

      # Print all post titles
      query = from p in Post,
           select: p.title
      {:ok, stage} = Ecto.Adapters.SQL.stream(MyRepo, query)
      stage
      |> Flow.from_stage()
      |> Flow.each(&IO.inspect/1)
      |> Flow.start_link()
  """

  @callback stream(repo :: module, queryable :: Ecto.Query.t, opts :: Keyword.t) ::
    GenServer.on_start()
  def stream(repo, queryable, opts \\ []) do
    stream = apply(repo, :stream, [queryable, opts])
    start =
      fn() ->
        acc = {:suspend, {0, []}}
        {:suspended, _, cont} = Enumerable.reduce(stream, acc, &stream_reduce/2)
        {repo, :cont, cont}
      end
    start_link(repo, :producer, start, &stream_handle/2, &stream_stop/2, opts)
  end

  ## Helpers

  defp stream_reduce(v, {1, acc}) do
    {:suspend, {0, [v | acc]}}
  end
  defp stream_reduce(v, {n, acc}) do
    {:cont, {n-1, [v | acc]}}
  end

  defp stream_handle(n, {repo, :cont, cont}) when n > 0 do
    case cont.({:cont, {n, []}}) do
      {:suspended, {0, acc}, cont} ->
        {Enum.reverse(acc), {repo, :cont, cont}}
      {status, {_, acc}} when status in [:halted, :done] ->
        GenStage.async_notify(self(), {:producer, status})
        {Enum.reverse(acc), {repo, status}}
    end
  end
  defp stream_handle(_, {_repo, status} = state) do
    GenStage.async_notify(self(), {:producer, status})
    {[], state}
  end

  defp stream_stop(reason, {repo, :cont, cont}) do
    _ = cont.({:halt, {0, []}})
    stream_stop(repo, reason)
  end
  defp stream_stop(reason, {repo, status}) when status in [:halted, :done] do
    stream_stop(repo, reason)
  end

  defp stream_stop(_, :normal) do
    :ok
  end
  defp stream_stop(repo, reason) do
    apply(repo, :rollback, [reason])
  end
end
