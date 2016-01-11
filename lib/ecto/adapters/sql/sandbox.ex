defmodule Ecto.Adapters.SQL.Sandbox do
  @moduledoc ~S"""
  TODO: Rewrite docs.

  Starts a transaction for test.

  This function work by starting a transaction and storing the connection
  back in the pool with an open transaction. On every test, we restart
  the test transaction rolling back to the appropriate savepoint.

  **IMPORTANT:** Test transactions only work if the connection pool is
  `Ecto.Adapters.SQL.Sandbox`

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
      # From now, all tests happen inside a transaction
      Ecto.Adapters.SQL.begin_test_transaction(TestRepo)

      defmodule PostTest do
        # Tests that use the shared repository cannot be async
        use ExUnit.Case

        setup do
          # Go back to a clean slate at the beginning of every test
          Ecto.Adapters.SQL.restart_test_transaction(TestRepo)
          :ok
        end

        test "create comment" do
          assert %Post{} = TestRepo.insert!(%Post{})
        end
      end

  In some cases, you may want to start the test transaction only
  for specific tests and then roll it back. You can do it as:

      defmodule PostTest do
        # Tests that use the shared repository cannot be async
        use ExUnit.Case

        setup_all do
          # Wrap this case in a transaction
          Ecto.Adapters.SQL.begin_test_transaction(TestRepo)

          # Roll it back once we are done
          on_exit fn ->
            Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
          end

          :ok
        end

        setup do
          # Go back to a clean slate at the beginning of every test
          Ecto.Adapters.SQL.restart_test_transaction(TestRepo)
          :ok
        end

        test "create comment" do
          assert %Post{} = TestRepo.insert!(%Post{})
        end
      end

  """

  @doc """
  Retuns the begin transaction query for sandbox.
  """
  @callback begin_sandbox :: term

  @doc """
  Retuns the rollback transaction query for sandbox.
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

  def enable(repo) do
    {name, opts} = repo.__pool__

    if opts[:pool] != DBConnection.Ownership do
      raise """
      cannot enable sandbox with pool #{inspect opts[:pool]}.
      To use the SQL Sandbox, configure your repository pool as:

            pool: #{inspect __MODULE__}
      """
    end

    # Check in any previous checked out connection from this process
    _ = DBConnection.Ownership.ownership_checkin(name, opts)

    DBConnection.Ownership.ownership_mode(name, :manual, opts)
  end

  def checkout(repo) do
    {name, opts} = proxy_pool(repo)
    DBConnection.Ownership.ownership_checkout(name, opts)
  end

  defp proxy_pool(repo) do
    {name, opts} = repo.__pool__
    {pool, opts} = Keyword.pop(opts, :ownership_pool, DBConnection.Poolboy)
    {name, [repo: repo, sandbox_pool: pool, ownership_pool: Pool] ++ opts}
  end
end
