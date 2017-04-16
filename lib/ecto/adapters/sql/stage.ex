defmodule Ecto.Adapters.SQL.Stage do
  @moduledoc """
  A `GenStage` process that encapsulates a SQL transaction.

  ### Options

    * `:name` - A name to register the started process (see the `:name` option
    in `GenServer.start_link/3`)

  See the "Shared options" section at the `Ecto.Repo` documentation. All options
  are passed to the `GenStage` on init.
  """

  @doc """
  Start link a `GenStage` producer that will run a transaction for its duration.

  The first argument is the repo, the second argument is the start function,
  the third argument is the handle demand function, the fourth argument is the
  stop function and the optional fiftth argument are the options.

  The start function is a 0-arity anonymous function. This is called after the
  transaction begins but before `producer/5` returns. It should return the
  accumulator or call `repo.rollback/1` to stop the `GenStage`.

  The handle demand function is a 2-arity anonymous function. The first argument
  is the `demand`, and the second argument is the accumulator. This function
  returns a 2-tuple, with first element as list of events to fulfil the demand
  and second element as the accumulator. If the producer has emitted all events
  (and so not fulfilled demand) it should call
  `GenStage.async_notify(self(), {:producer, :done | :halted}` to signal to
  consumers that it has finished. Also this function can rollback and stop the
  `GenStage` using `repo.rollback/1`.

  The stop function is a 2-arity anonymous function. The first argument is the
  terminate reason and the third argument is the accumulator. This function will
  only be called if connection is alive and the transaction has not been rolled
  back. If this function returns the transaction is committed. This function can
  rollback and stop the `GenStage` using `repo.rollback/1`.

  For options see "Options" in the module documentation.

  The `GenStage` process will behave like a `Flow` stage:

    * It will stop with reason `:normal` when the last consumer cancels
  """
  @spec producer(module, start :: (() -> acc),
    handle_demand :: ((demand :: pos_integer, acc) -> {[any], acc}),
    stop :: ((reason :: any, acc) -> any), Keyword.t) ::
    GenServer.on_start when acc: var
  def producer(repo, start, handle_demand, stop, opts \\ []) do
    fun = &DBConnection.Stage.producer/5
    Ecto.Adapters.SQL.stage(fun, repo, start, handle_demand, stop, opts) 
  end

  @doc """
  Start link a `GenStage` producer consumer that will run a transaction for its
  duration.

  The first argument is the repo, the second argument is the start function,
  the third argument is the handle events function, the fourth argument is the
  stop function and the optional fiftth argument are the options.

  The start function is a 0-arity anonymous function. This is called after the
  transaction begins but before `consumer_producer/5` returns. It should return
  the accumulator or call `repo.rollback/1` to stop the `GenStage`.

  The handle events function is a 2-arity anonymous function. The first argument
  is a list of incoming events, and the second argument is the accumulator. This
  function returns a 2-tuple, with first element as list of outgoing events and
  second element as the accumulator. Also this function can rollback and stop
  the `GenStage` using `repo.rollback/1`.

  The stop function is a 2-arity anonymous function. The first argument is the
  terminate reason and the second argument is the accumulator. This function
  will only be called if connection is alive and the transaction has not been
  rolled back. If this function returns the transaction is committed. This
  function can rollback and stop the `GenStage` using `repo.rollback/1`.

  For options see "Options" in the module documentation.

  The `GenStage` process will behave like a `Flow` stage:

    * It will stop with reason `:normal` when the last consumer cancels
    * It will notify consumers that it is done when all producers have cancelled
    or notified that they are done or halted
    * It will not send demand to new producers when all producers have notified
    that they are done or halted
  """
  @spec producer_consumer(repo :: module, start :: (() -> acc),
    handle_events :: ((events_in :: [any], acc) -> {events_out :: [any], acc}),
    stop :: ((reason :: any, acc) -> any), Keyword.t) ::
    GenServer.on_start when acc: var
  def producer_consumer(repo, start, handle_events, stop, opts \\ []) do
    fun = &DBConnection.Stage.producer_consumer/5
    Ecto.Adapters.SQL.stage(fun, repo, start, handle_events, stop, opts)
  end

  @doc """
  Start link a `GenStage` consumer that will run a transaction for its duration.

  The first argument is the repo, the second argument is the start function,
  the third argument is the handle events function, the fourth argument is the
  stop function and the optional fiftth argument are the options.

  The start function is a 0-arity anonymous function. This is called after the
  transaction begins but before `consumer/5` returns. It should return the
  accumulator or call `repo.rollback/1` to stop the `GenStage`.

  The handle events function is a 2-arity anonymous function. The first argument
  is the list of events, and the second argument is the accumulator. This
  function returns a 2-tuple, with first element is an empty list (as no
  outgoing events) and second element as the accumulator. Also this function can
  rollback and stop the `GenStage` using `repo.rollback/1`.

  The stop function is a 2-arity anonymous function. The first argument is the
  terminate reason and the second argument is the accumulator. This function
  will only be called if connection is alive and the transaction has not been
  rolled back. If this function returns the transaction is committed. This
  function can rollback and stop the `GenStage` using `repo.rollback/1`.

  See the "Shared options" section at the `Ecto.Repo` documentation.

  The `GenStage` process will behave like a `Flow` stage:

    * It will cancel new and remaining producers when all producers have
    notified that they are done or halted and it is a `:consumer`
  """
  @spec consumer(repo :: module, start :: (() -> acc),
    handle_events :: ((events_in :: [any], acc) -> {[], acc}),
    stop :: ((reason :: any, acc) -> any), Keyword.t) ::
    GenServer.on_start when acc: var
  def consumer(pool, start, handle_events, stop, opts \\ []) do
    fun = &DBConnection.Stage.consumer/5
    Ecto.Adapters.SQL.stage(fun, pool, start, handle_events, stop, opts)
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

  For more options see "Options" in the module documentation.

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
  @spec stream(repo :: module, queryable :: Ecto.Query.t, opts :: Keyword.t) ::
    GenServer.on_start()
  def stream(repo, queryable, opts \\ []) do
    stream = apply(repo, :stream, [queryable, opts])
    start =
      fn() ->
        acc = {:suspend, {0, []}}
        {:suspended, _, cont} = Enumerable.reduce(stream, acc, &stream_reduce/2)
        {repo, :cont, cont}
      end
    producer(repo, start, &stream_handle/2, &stream_stop/2, opts)
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
