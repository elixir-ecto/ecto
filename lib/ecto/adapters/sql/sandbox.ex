defmodule Ecto.Adapters.SQL.Sandbox do
  @moduledoc ~S"""
  A pool for concurrent transactional tests.

  The sandbox pool is implemented on top of an ownership mechanism.
  When started, the pool is in automatic mode, which means the
  repository will automatically check connections out as with any
  other pool.

  The `mode/2` function can be used to change the pool mode to
  manual or shared. In both modes, the connection must be explicitly
  checked out before use. When explicit checkouts are made, the
  sandbox will wrap the connection in a transaction by default and
  control who has access to it. This means developers have a safe
  mechanism for running concurrent tests against the database.

  ## Database support

  While both PostgreSQL and MySQL support SQL Sandbox, only PostgreSQL
  supports concurrent tests while running the SQL Sandbox. Therefore, do
  not run concurrent tests with MySQL as you may run into deadlocks due to
  its transaction implementation.

  ## Example

  The first step is to configure your database to use the
  `Ecto.Adapters.SQL.Sandbox` pool. You set those options in your
  `config/config.exs` (or preferably `config/test.exs`) if you
  haven't yet:

      config :my_app, Repo,
        pool: Ecto.Adapters.SQL.Sandbox

  Now with the test database properly configured, you can write
  transactional tests:

      # At the end of your test_helper.exs
      # Set the pool mode to manual for explicit checkouts
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)

      defmodule PostTest do
        # Once the mode is manual, tests can also be async
        use ExUnit.Case, async: true

        setup do
          # Explicitly get a connection before each test
          :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
        end

        test "create post" do
          # Use the repository as usual
          assert %Post{} = Repo.insert!(%Post{})
        end
      end

  ## Collaborating processes

  The example above is straight-forward because we have only
  a single process using the database connection. However,
  sometimes a test may need to interact with multiple processes,
  all using the same connection so they all belong to the same
  transaction.

  Before we discuss solutions, let's see what happens if we try
  to use a connection from a new process without explicitly
  checking it out first:

      setup do
        # Explicitly get a connection before each test
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
      end

      test "create two posts, one sync, another async" do
        task = Task.async(fn ->
          Repo.insert!(%Post{title: "async"})
        end)
        assert %Post{} = Repo.insert!(%Post{title: "sync"})
        assert %Post{} = Task.await(task)
      end

  The test above will fail with an error similar to:

      ** (RuntimeError) cannot find ownership process for #PID<0.35.0>

  That's because the `setup` block is checking out the connection only
  for the test process. Once we spawn a Task, there is no connection
  assigned to it and it will fail.

  The sandbox module provides two ways of doing so, via allowances or
  by running in shared mode.

  ### Allowances

  The idea behind allowances is that you can explicitly tell a process
  which checked out connection it should use, allowing multiple processes
  to collaborate over the same connection. Let's give it a try:

      test "create two posts, one sync, another async" do
        parent = self()
        task = Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
          Repo.insert!(%Post{title: "async"})
        end)
        assert %Post{} = Repo.insert!(%Post{title: "sync"})
        assert %Post{} = Task.await(task)
      end

  And that's it, by calling `allow/3`, we are explicitly assigning
  the parent's connection (i.e. the test process' connection) to
  the task.

  Because allowances use an explicit mechanism, their advantage
  is that you can still run your tests in async mode. The downside
  is that you need to explicitly control and allow every single
  process. This is not always possible. In such cases, you will
  want to use shared mode.

  ### Shared mode

  Shared mode allows a process to share its connection with any other
  process automatically, without relying on explicit allowances.
  Let's change the example above to use shared mode:

      setup do
        # Explicitly get a connection before each test
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
        # Setting the shared mode must be done only after checkout
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      end

      test "create two posts, one sync, another async" do
        task = Task.async(fn ->
          Repo.insert!(%Post{title: "async"})
        end)
        assert %Post{} = Repo.insert!(%Post{title: "sync"})
        assert %Post{} = Task.await(task)
      end

  By calling `mode({:shared, self()})`, any process that needs
  to talk to the database will now use the same connection as the
  one checked out by the test process during the `setup` block.

  Make sure to always check a connection out before setting the mode
  to `{:shared, self()}`.

  The advantage of shared mode is that by calling a single function,
  you will ensure all upcoming processes and operations will use that
  shared connection, without a need to explicitly allow them. The
  downside is that tests can no longer run concurrently in shared mode.

  ### Summing up

  There are two mechanisms for explicit ownerships:

    * Using allowances - requires explicit allowances via `allow/3`.
      Tests may run concurrently.

    * Using shared mode - does not require explicit allowances.
      Tests cannot run concurrently.

  ## FAQ

  When running the sandbox mode concurrently, developers may run into
  issues we explore in the upcoming sections.

  ### "owner exited while client is still running"

  In some situations, you may see error reports similar to the one below:

      21:57:43.910 [error] Postgrex.Protocol (#PID<0.284.0>) disconnected:
          ** (DBConnection.Error) owner #PID<> exited while client #PID<> is still running

  Such errors are usually followed by another error report from another
  process that failed while executing a database query.

  To understand the failure, we need to answer the question: who are the
  owner and client processes? The owner process is the one that checks
  out the connection, which, in the majority of cases, is the test process,
  the one running your tests. In other words, the error happens because
  the test process has finished, either because the test succeeded or
  because it failed, while the client process was trying to get information
  from the database. Since the owner process, the one that owns the
  connection, no longer exists, Ecto will check the connection back in
  and notify the client process using the connection that the connection
  owner is no longer available.

  This can happen in different situations. For example, imagine you query
  a GenServer in your test that is using a database connection:

      test "gets results from GenServer" do
        {:ok, pid} = MyAppServer.start_link()
        Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
        assert MyAppServer.get_my_data_fast(timeout: 1000) == [...]
      end

  In the test above, we spawn the server and allow it to perform database
  queries using the connection owned by the test process. Since we gave
  a timeout of 1 second, in case the database takes longer than one second
  to reply, the test process will fail, due to the timeout, making the
  "owner down" message to be printed because the server process is still
  waiting on a connection reply.

  In some situations, such failures may be intermittent. Imagine that you
  allow a process that queries the database every half second:

      test "queries periodically" do
        {:ok, pid} = PeriodicServer.start_link()
        Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
        # more tests
      end

  Because the server is querying the database from time to time, there is
  a chance that, when the test exists, the periodic process may be querying
  the database, regardless of test success or failure.

  ### "owner timed out because it owned the connection for longer than Nms"

  In some situations, you may see error reports similar to the one below:

      09:56:43.081 [error] Postgrex.Protocol (#PID<>) disconnected:
          ** (DBConnection.ConnectionError) owner #PID<> timed out
          because it owned the connection for longer than 15000ms

  If you have a long running test (or you're debugging with IEx.pry), the timeout for the connection ownership may
  be too short.  You can increase the timeout by setting the
  `:ownership_timeout` options for your repo config in `config/config.exs` (or preferably in `config/test.exs`):

      config :my_app, MyApp.Repo,
        ownership_timeout: NEW_TIMEOUT_IN_MILLISECONDS

  The `:ownership_timeout` option is part of
  [`DBConnection.Ownership`](https://hexdocs.pm/db_connection/DBConnection.Ownership.html)
  and defaults to 15000ms. Timeouts are given as integers in milliseconds.

  Alternately, if this is an issue for only a handful of long-running tests,
  you can pass an `:ownership_timeout` option when calling
  `Ecto.Adapters.SQL.Sandbox.checkout/2` instead of setting a longer timeout
  globally in your config.

  ### Database locks and deadlocks

  Since the sandbox relies on concurrent transactional tests, there is
  a chance your tests may trigger deadlocks in your database. This is
  specially true with MySQL, where the solutions presented here are not
  enough to avoid deadlocks and therefore making the use of concurrent tests
  with MySQL prohibited.

  However, even on databases like PostgreSQL, performance degradations or
  deadlocks may still occur. For example, imagine multiple tests are
  trying to insert the same user to the database. They will attempt to
  retrieve the same database lock, causing only one test to succeed and
  run while all other tests wait for the lock.

  In other situations, two different tests may proceed in a way that
  each test retrieves locks desired by the other, leading to a situation
  that cannot be resolved, a deadlock. For instance:

      Transaction 1:                Transaction 2:
      begin
                                    begin
      update posts where id = 1
                                    update posts where id = 2
                                    update posts where id = 1
      update posts where id = 2
                            **deadlock**

  There are different ways to avoid such problems. One of them is
  to make sure your tests work on distinct data. Regardless of
  your choice between using fixtures or factories for test data,
  make sure you get a new set of data per test. This is specially
  important for data that is meant to be unique like user emails.

  For example, instead of:

      def insert_user do
        Repo.insert! %User{email: "sample@example.com"}
      end

  prefer:

      def insert_user do
        Repo.insert! %User{email: "sample-#{counter()}@example.com"}
      end

      defp counter do
        System.unique_integer [:positive]
      end

  Deadlocks may happen in other circumstances. If you believe you
  are hitting a scenario that has not been described here, please
  report an issue so we can improve our examples. As a last resort,
  you can always disable the test triggering the deadlock from
  running asynchronously by setting  "async: false".
  """

  defmodule Connection do
    @moduledoc false
    if Code.ensure_loaded?(DBConnection) do
      @behaviour DBConnection
    end

    def connect(_opts) do
      raise "should never be invoked"
    end

    def disconnect(err, {conn_mod, state, _in_transaction?}) do
      conn_mod.disconnect(err, state)
    end

    def checkout(state), do: proxy(:checkout, state, [])
    def checkin(state), do: proxy(:checkin, state, [])
    def ping(state), do: proxy(:ping, state, [])

    def handle_begin(opts, {conn_mod, state, false}) do
      opts = [mode: :savepoint] ++ opts

      case conn_mod.handle_begin(opts, state) do
        {:ok, value, state} ->
          {:ok, value, {conn_mod, state, true}}
        {kind, err, state} ->
          {kind, err, {conn_mod, state, false}}
      end
    end
    def handle_commit(opts, {conn_mod, state, true}) do
      opts = [mode: :savepoint] ++ opts
      proxy(:handle_commit, {conn_mod, state, false}, [opts])
    end
    def handle_rollback(opts, {conn_mod, state, true}) do
      opts = [mode: :savepoint] ++ opts
      proxy(:handle_rollback, {conn_mod, state, false}, [opts])
    end

    def handle_prepare(query, opts, state),
      do: proxy(:handle_prepare, state, [query, maybe_savepoint(opts, state)])
    def handle_execute(query, params, opts, state),
      do: proxy(:handle_execute, state, [query, params, maybe_savepoint(opts, state)])
    def handle_close(query, opts, state),
      do: proxy(:handle_close, state, [query, maybe_savepoint(opts, state)])
    def handle_declare(query, params, opts, state),
      do: proxy(:handle_declare, state, [query, params, maybe_savepoint(opts, state)])
    def handle_first(query, cursor, opts, state),
      do: proxy(:handle_first, state, [query, cursor, maybe_savepoint(opts, state)])
    def handle_next(query, cursor, opts, state),
      do: proxy(:handle_next, state, [query, cursor, maybe_savepoint(opts, state)])
    def handle_deallocate(query, cursor, opts, state),
      do: proxy(:handle_deallocate, state, [query, cursor, maybe_savepoint(opts, state)])
    def handle_info(msg, state),
      do: proxy(:handle_info, state, [msg])

    defp maybe_savepoint(opts, {_, _, in_transaction?}) do
      if not in_transaction? and Keyword.get(opts, :sandbox_subtransaction, true) do
        [mode: :savepoint] ++ opts
      else
        opts
      end
    end

    defp proxy(fun, {conn_mod, state, in_transaction?}, args) do
      result = apply(conn_mod, fun, args ++ [state])
      pos = :erlang.tuple_size(result)
      :erlang.setelement(pos, result, {conn_mod, :erlang.element(pos, result), in_transaction?})
    end
  end

  defmodule Pool do
    @moduledoc false
    if Code.ensure_loaded?(DBConnection) do
      @behaviour DBConnection.Pool
    end

    def ensure_all_started(_opts, _type) do
      raise "should never be invoked"
    end

    def start_link(_module, _opts) do
      raise "should never be invoked"
    end

    def child_spec(_module, _opts, _child_opts) do
      raise "should never be invoked"
    end

    def checkout(pool, opts) do
      pool_mod = opts[:sandbox_pool]

      case pool_mod.checkout(pool, opts) do
        {:ok, pool_ref, conn_mod, conn_state} ->
          case conn_mod.handle_begin([mode: :transaction] ++ opts, conn_state) do
            {:ok, _, conn_state} ->
              {:ok, pool_ref, Connection, {conn_mod, conn_state, false}}
            {_error_or_disconnect, err, conn_state} ->
              pool_mod.disconnect(pool_ref, err, conn_state, opts)
          end
        error ->
          error
      end
    end

    def checkin(pool_ref, {conn_mod, conn_state, _in_transaction?}, opts) do
      pool_mod = opts[:sandbox_pool]
      case conn_mod.handle_rollback([mode: :transaction] ++ opts, conn_state) do
        {:ok, _, conn_state} ->
          pool_mod.checkin(pool_ref, conn_state, opts)
        {_error_or_disconnect, err, conn_state} ->
          pool_mod.disconnect(pool_ref, err, conn_state, opts)
      end
    end

    def disconnect(owner, exception, {_conn_mod, conn_state, _in_transaction?}, opts) do
      opts[:sandbox_pool].disconnect(owner, exception, conn_state, opts)
    end

    def stop(owner, reason, {_conn_mod, conn_state, _in_transaction?}, opts) do
      opts[:sandbox_pool].stop(owner, reason, conn_state, opts)
    end
  end

  @doc """
  Sets the mode for the `repo` pool.

  The mode can be `:auto`, `:manual` or `:shared`.
  """
  def mode(repo, mode)
      when mode in [:auto, :manual]
      when elem(mode, 0) == :shared and is_pid(elem(mode, 1)) do
    {name, opts} = repo.__pool__

    if opts[:pool] != DBConnection.Ownership do
      raise """
      cannot configure sandbox with pool #{inspect opts[:pool]}.
      To use the SQL Sandbox, configure your repository pool as:

            pool: #{inspect __MODULE__}
      """
    end

    # If the mode is set to anything but shared, let's
    # automatically checkin the current connection to
    # force it to act according to the chosen mode.
    if mode in [:auto, :manual] do
      checkin(repo, [])
    end

    DBConnection.Ownership.ownership_mode(name, mode, opts)
  end

  @doc """
  Checks a connection out for the given `repo`.

  The process calling `checkout/2` will own the connection
  until it calls `checkin/2` or until it crashes when then
  the connection will be automatically reclaimed by the pool.

  ## Options

    * `:sandbox` - when true the connection is wrapped in
      a transaction. Defaults to true.

    * `:isolation` - set the query to the given isolation level

    * `:ownership_timeout` - limits how long the connection can be
      owned. Defaults to the compiled value from your repo config in
      `config/config.exs` (or preferably in `config/test.exs`), or
      15000 ms if not set.
  """
  def checkout(repo, opts \\ []) do
    {name, pool_opts} =
      if Keyword.get(opts, :sandbox, true) do
        proxy_pool(repo)
      else
        repo.__pool__
      end

    pool_opts_overrides = Keyword.take(opts, [:ownership_timeout])
    pool_opts = Keyword.merge(pool_opts, pool_opts_overrides)

    case DBConnection.Ownership.ownership_checkout(name, pool_opts) do
      :ok ->
        if isolation = opts[:isolation] do
          set_transaction_isolation_level(repo, isolation)
        end
        :ok
      other ->
        other
    end
  end

  defp set_transaction_isolation_level(repo, isolation) do
    query = "SET TRANSACTION ISOLATION LEVEL #{isolation}"
    case Ecto.Adapters.SQL.query(repo, query, [], sandbox_subtransaction: false) do
      {:ok, _} ->
        :ok
      {:error, error} ->
        checkin(repo, [])
        raise error
    end
  end

  @doc """
  Checks in the connection back into the sandbox pool.
  """
  def checkin(repo, _opts \\ []) do
    {name, opts} = repo.__pool__
    DBConnection.Ownership.ownership_checkin(name, opts)
  end

  @doc """
  Allows the `allow` process to use the same connection as `parent`.
  """
  def allow(repo, parent, allow, _opts \\ []) do
    {name, opts} = repo.__pool__
    DBConnection.Ownership.ownership_allow(name, parent, allow, opts)
  end

  defp proxy_pool(repo) do
    {name, opts} = repo.__pool__
    {pool, opts} = Keyword.pop(opts, :ownership_pool, DBConnection.Poolboy)
    {name, [repo: repo, sandbox_pool: pool, ownership_pool: Pool] ++ opts}
  end
end
