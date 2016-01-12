defmodule Ecto.Adapters.SQL.Sandbox do
  @moduledoc ~S"""
  A pool for concurrent transactional tests.

  The sandbox pool is implemented on top of an ownership mechanism.
  When started, the pool is in automatic mode, which means using
  the repository will automatically check connections out as with
  any other pool. The only difference is that connections are not
  checked back in automatically but by explicitly calling `checkin/2`.

  The `mode/2` function can be used to change the pool mode to
  `:manual`. In this case, each connection must be explicitly
  checked out before use. This is useful when paired with
  `checkout/2` which by default wraps the connection in a transaction.
  This means developers have a safe mechanism for running concurrent
  tests against the database.

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

        test "create comment" do
          # Use the repository as usual
          assert %Post{} = TestRepo.insert!(%Post{})
        end
      end

  ## Options

  Because the sandbox is implemented on top of the
  `DBConnection.Ownership` module, you can check the module
  documentation to see which options available to configure
  the ownership mode when desired.
  """

  @doc """
  Returns the begin transaction query for sandbox.
  """
  @callback begin_sandbox :: term

  @doc """
  Returns the rollback transaction query for sandbox.
  """
  @callback rollback_sandbox :: term

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
          query = opts[:repo].__sql__.begin_sandbox
          case sandbox_query(query, opts, conn_mod, conn_state) do
            {:ok, _, conn_state} ->
              {:ok, pool_ref, Connection, {conn_mod, conn_state}}
            {_error_or_disconnect, err, conn_state} ->
              pool_mod.disconnect(pool_ref, err, conn_state, opts)
          end
        :error ->
          :error
      end
    end

    def checkin(pool_ref, {conn_mod, conn_state}, opts) do
      pool_mod = opts[:sandbox_pool]
      query = opts[:repo].__sql__.rollback_sandbox
      case sandbox_query(query, opts, conn_mod, conn_state) do
        {:ok, _, conn_state} ->
          pool_mod.checkin(pool_ref, conn_state, opts)
        {_error_or_disconnect, err, conn_state} ->
          pool_mod.disconnect(pool_ref, err, conn_state, opts)
      end
    end

    def disconnect(owner, exception, state, opts) do
      opts[:sandbox_pool].disconnect(owner, exception, state, opts)
    end

    def stop(owner, reason, state, opts) do
      opts[:sandbox_pool].stop(owner, reason, state, opts)
    end

    defp sandbox_query(query, opts, conn_mod, conn_state) do
      query = DBConnection.Query.parse(query, opts)
      case conn_mod.handle_prepare(query, opts, conn_state) do
        {:ok, query, conn_state} ->
          query = DBConnection.Query.describe(query, opts)
          sandbox_execute(query, opts, conn_mod, conn_state)
        other ->
          other
      end
    end

    defp sandbox_execute(query, opts, conn_mod, conn_state) do
      params = DBConnection.Query.encode(query, [], opts)
      conn_mod.handle_execute_close(query, params, opts, conn_state)
    end
  end

  @doc """
  Sets the mode for the `repo` pool.

  The mode can be `:auto` or `:manual`.
  """
  def mode(repo, mode) when mode in [:auto, :manual] do
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
      a transaction. Defaults to true. WHen

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
  Allows the `allow` process to use the connection owned by `owner`.
  """
  def allow(repo, owner, allow, _opts \\ []) do
    {name, opts} = repo.__pool__
    DBConnection.Ownership.ownership_allow(name, owner, allow, opts)
  end

  defp proxy_pool(repo) do
    {name, opts} = repo.__pool__
    {pool, opts} = Keyword.pop(opts, :ownership_pool, DBConnection.Poolboy)
    {name, [repo: repo, sandbox_pool: pool, ownership_pool: Pool] ++ opts}
  end
end
