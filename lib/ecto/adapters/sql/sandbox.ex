defmodule Ecto.Adapters.SQL.Sandbox do
  @moduledoc ~S"""
  A pool for concurrent transactional tests.

  The sandbox pool is implemented on top of an ownership mechanism.
  When started, the pool is in automatic mode, which means using
  the repository will automatically check connections out as with
  any other pool. The only difference is that connections are not
  checked back in automatically but by explicitly calling `checkin/2`.

  The `mode/2` function can be used to change the pool mode to
  manual or shared. In both modes, the connection must be explicitly
  checked out before use. When explicit checkouts are made, the sandbox
  will wrap the connection in a transaction by default. This means developers
  have a safe mechanism for running concurrent tests against the database.

  ## Example

  The first step is to configure your database to use the
  `Ecto.Adapters.SQL.Sandbox` pool. You set those options in your
  `config/config.exs`:

      config :my_app, Repo,
        pool: Ecto.Adapters.SQL.Sandbox

  Since you don't want those options in your production database, we
  typically recommend to create a `config/test.exs` and add the
  following to the bottom of your `config/config.exs` file:

      import_config "config/#{Mix.env}.exs"

  Now with the test database properly configured, you can write
  transactional tests:

      # At the end of your test_helper.exs
      # Set the pool mode to manual for explicitly checkouts
      Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)

      defmodule PostTest do
        # Once the model is manual, tests can also be async
        use ExUnit.Case, async: true

        setup do
          # Explicitly get a connection before each test
          :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
        end

        test "create post" do
          # Use the repository as usual
          assert %Post{} = TestRepo.insert!(%Post{})
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
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
      end

      test "create two posts, one sync, another async" do
        task = Task.async(fn ->
          TestRepo.insert!(%Post{title: "async"})
        end)
        assert %Post{} = TestRepo.insert!(%Post{title: "sync"})
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
          Ecto.Adapters.SQL.Sandbox.allow(TestRepo, parent, self())
          TestRepo.insert!(%Post{title: "async"})
        end)
        assert %Post{} = TestRepo.insert!(%Post{title: "sync"})
        assert %Post{} = Task.await(task)
      end

  And that's it, by calling `allow/3`, we are explicitly assigning
  the parent's connection (i.e. the test process' connection) to
  the task.

  Because allowances uses an explicit mechanism, their advantage
  is that you can still runs your tests in async mode. The downside
  is that you need to explicitly control and allow every single
  process. This is not always possible. In such cases, you will
  want to use shared mode.

  ### Shared mode

  Shared mode allows a process to share its connection with any other
  process automatically, without relying on explicit allowances.
  Let's change the example above to use shared mode:

      setup do
        # Explicitly get a connection before each test
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
        # Setting the shared mode must be done only after checkout
        Ecto.Adapters.SQL.Sandbox.mode(TestRepo, {:shared, self()})
      end

      test "create two posts, one sync, another async" do
        task = Task.async(fn ->
          TestRepo.insert!(%Post{title: "async"})
        end)
        assert %Post{} = TestRepo.insert!(%Post{title: "sync"})
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

  """

  defmodule Connection do
    @moduledoc false
    @behaviour DBConnection

    def connect({conn_mod, state}) do
      case conn_mod.init(state) do
        {:ok, state} -> {:ok, {conn_mod, state}}
        {:error, _} = err -> err
      end
    end

    def disconnect(err, {conn_mod, state}) do
      conn_mod.disconnect(err, state)
    end

    def checkout(state), do: proxy(:checkout, state, [])
    def checkin(state), do: proxy(:checkin, state, [])
    def ping(state), do: proxy(:ping, state, [])

    def handle_begin(opts, state) do
      opts = [mode: :savepoint] ++ opts
      proxy(:handle_begin, state, [opts])
    end
    def handle_commit(opts, state) do
      opts = [mode: :savepoint] ++ opts
      proxy(:handle_commit, state, [opts])
    end
    def handle_rollback(opts, state) do
      opts = [mode: :savepoint] ++ opts
      proxy(:handle_rollback, state, [opts])
    end

    def handle_prepare(query, opts, state),
      do: proxy(:handle_prepare, state, [query, opts])
    def handle_execute(query, params, opts, state),
      do: proxy(:handle_execute, state, [query, params, opts])
    def handle_execute_close(query, params, opts, state),
      do: proxy(:handle_execute_close, state, [query, params, opts])
    def handle_close(query, opts, state),
      do: proxy(:handle_close, state, [query, opts])
    def handle_info(msg, state),
      do: proxy(:handle_info, state, [msg])

    defp proxy(fun, {conn_mod, state}, args) do
      result = apply(conn_mod, fun, args ++ [state])
      pos = :erlang.tuple_size(result)
      :erlang.setelement(pos, result, {conn_mod, :erlang.element(pos, result)})
    end
  end

  defmodule Pool do
    @moduledoc false
    @behaviour DBConnection.Pool

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
          case conn_mod.handle_begin([mode: :transaction]++opts, conn_state) do
            {:ok, _, conn_state} ->
              {:ok, pool_ref, Connection, {conn_mod, conn_state}}
            {_error_or_disconnect, err, conn_state} ->
              pool_mod.disconnect(pool_ref, err, conn_state, opts)
          end
        error ->
          error
      end
    end

    def checkin(pool_ref, {conn_mod, conn_state}, opts) do
      pool_mod = opts[:sandbox_pool]
      case conn_mod.handle_rollback([mode: :transaction]++opts, conn_state) do
        {:ok, _, conn_state} ->
          pool_mod.checkin(pool_ref, conn_state, opts)
        {_error_or_disconnect, err, conn_state} ->
          pool_mod.disconnect(pool_ref, err, conn_state, opts)
      end
    end

    def disconnect(owner, exception, {_conn_mod, conn_state}, opts) do
      opts[:sandbox_pool].disconnect(owner, exception, conn_state, opts)
    end

    def stop(owner, reason, {_conn_mod, conn_state}, opts) do
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

  """
  def checkout(repo, opts \\ []) do
    {name, opts} =
      if Keyword.get(opts, :sandbox, true) do
        proxy_pool(repo)
      else
        repo.__pool__
      end

    DBConnection.Ownership.ownership_checkout(name, opts)
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
