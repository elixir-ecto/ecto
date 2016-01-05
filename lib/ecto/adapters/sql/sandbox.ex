defmodule Ecto.Adapters.SQL.Sandbox do
  @moduledoc """
  Start a pool with a single sandboxed SQL connection.
  """

  defmodule Query do
    defstruct [:request]
  end

  defmodule Result do
    defstruct [:value]
  end

  @behaviour DBConnection
  @behaviour DBConnection.Pool

  defstruct [:mod, :state, :status, :adapter]

  @doc false
  def mode(pool) do
    DBConnection.execute!(pool, %Query{request: :mode}, [], [pool: __MODULE__])
  end

  @doc false
  def start_link(mod, opts) do
    DBConnection.Connection.start_link(__MODULE__, opts(mod, opts))
  end

  @doc false
  def child_spec(mod, opts, child_opts \\ []) do
    DBConnection.Connection.child_spec(__MODULE__, opts(mod, opts), child_opts)
  end

  @doc false
  def checkout(pool, opts) do
    DBConnection.Connection.checkout(pool, opts(opts))
  end

  @doc false
  def checkin(pool, state, opts) do
    DBConnection.Connection.checkin(pool, state, opts(opts))
  end

  @doc false
  def disconnect(pool, err, state, opts) do
    DBConnection.Connection.disconnect(pool, err, state, opts(opts))
  end

  @doc false
  def stop(pool, reason, state, opts) do
    DBConnection.Connection.stop(pool, reason, state, opts(opts))
  end

  @doc false
  def connect(opts) do
    mod     = Keyword.fetch!(opts, :sandbox)
    adapter = Module.concat(Keyword.fetch!(opts, :adapter), Connection)
    case apply(mod, :connect, [opts]) do
      {:ok, state} ->
        s = %__MODULE__{mod: mod, state: state, status: :run, adapter: adapter}
        {:ok, s}
      {:error, _} = error ->
        error
    end
  end

  @doc false
  def checkout(s), do: handle(s, :checkout, [], :no_result)

  @doc false
  def checkin(s), do: handle(s, :checkin, [], :no_result)

  @doc false
  def ping(s), do: handle(s, :ping, [], :no_result)

  @doc false
  def handle_begin(opts, %{status: :run} = s) do
    transaction_handle(s, :handle_begin, opts, :transaction)
  end
  def handle_begin(opts, %{status: :sandbox} = s) do
    sandbox_transaction(s, :savepoint, opts, :sandbox_transaction)
  end

  @doc false
  def handle_commit(opts, %{status: :transaction} = s) do
    transaction_handle(s, :handle_commit, opts, :run)
  end
  def handle_commit(_, %{status: :sandbox_transaction} = s) do
    {:ok, %{s | status: :sandbox}}
  end

  @doc false
  def handle_rollback(opts, %{status: :transaction} = s) do
    transaction_handle(s, :handle_rollback, opts, :run)
  end
  def handle_rollback(opts, %{status: :sandbox_transaction} = s) do
    sandbox_transaction(s, :rollback_to_savepoint, opts, :sandbox)
  end

  @doc false
  def handle_prepare(query, opts, s) do
    handle(s, :handle_prepare, [query, opts], :result)
  end

  @doc false
  def handle_execute(%Query{request: request}, [], opts, s) do
    handle_request(request, opts, s)
  end
  def handle_execute(query, params, opts, s) do
    handle(s, :handle_execute, [query, params, opts], :execute)
  end

  @doc false
  def handle_execute_close(query, params, opts, s) do
    handle(s, :handle_execute_close, [query, params, opts], :execute)
  end

  @doc false
  def handle_close(query, opts, s) do
    handle(s, :handle_close, [query, opts], :no_result)
  end

  @doc false
  def handle_info(msg, s) do
    handle(s, :handle_info, [msg], :no_result)
  end

  @doc false
  def disconnect(err, %{mod: mod, status: status, state: state}) do
    :ok = apply(mod, :disconnect, [err, state])
    if status in [:sandbox, :sandbox_transaction] do
      raise err
    else
      :ok
    end
  end

  ## Helpers

  defp opts(mod, opts), do: [sandbox: mod] ++ opts(opts)

  defp opts(opts), do: [pool: DBConnection.Connection] ++ opts

  defp handle(%{mod: mod, state: state} = s, callback, args, return) do
    case apply(mod, callback, args ++ [state]) do
      {:ok, state} when return == :no_result ->
        {:ok, %{s | state: state}}
      {:ok, result, state} when return in [:result, :execute] ->
        {:ok, result, %{s | state: state}}
      {:prepare, state} when return == :execute ->
        {:prepare, %{s | state: state}}
      {error, err, state} when error in [:disconnect, :error] ->
        {error, err, %{s | state: state}}
      other ->
        other
    end
  end

  defp transaction_handle(s, callback, opts, new_status) do
    %{mod: mod, state: state} = s
    case apply(mod, callback, [opts, state]) do
      {:ok, state} ->
        {:ok, %{s | status: new_status, state: state}}
      {:error, err, state} ->
        {:error, err, %{s | status: :run, state: state}}
      {:disconnect, err, state} ->
        {:disconnect, err, %{s | state: state}}
      other ->
        other
    end
  end

  defp handle_request(:mode, _, %{status: status} = s)
  when status in [:run, :transaction] do
    {:ok, %Result{value: :raw}, s}
  end
  defp handle_request(:mode, _, %{status: status} = s)
  when status in [:sandbox, :sandbox_transaction] do
    {:ok, %Result{value: :sandbox}, s}
  end
  defp handle_request(req, _, %{status: status} = s)
  when status in [:transaction, :sandbox_transaction] do
    err = RuntimeError.exception("cannot #{req} test transaction inside transaction")
    {:error, err, s}
  end
  defp handle_request(:begin, opts, %{status: :run} = s) do
    sandbox_begin(s, opts)
  end
  defp handle_request(:begin, _, s) do
    err = RuntimeError.exception("cannot begin test transaction inside test transaction")
    {:error, err, s}
  end
  defp handle_request(:restart, opts, %{status: :sandbox} = s) do
    sandbox_restart(s, opts)
  end
  defp handle_request(:restart, opts, %{status: :run} = s) do
    sandbox_begin(s, opts)
  end
  defp handle_request(:rollback, opts, %{status: :sandbox} = s) do
    sandbox_rollback(s, opts)
  end
  defp handle_request(:rollback, _, s) do
    {:ok, %Result{value: :ok}, s}
  end

  defp sandbox_begin(s, opts) do
    case transaction_handle(s, :handle_begin, opts, :sandbox) do
      {:ok, %{adapter: adapter} = s} ->
        savepoint_query =
          "ecto_sandbox"
          |> adapter.savepoint()
          |> adapter.query()
        sandbox_query(savepoint_query, opts, s, :disconnect)
      other ->
        other
    end
  end

  defp sandbox_restart(%{adapter: adapter} = s, opts) do
    restart_query =
      "ecto_sandbox"
      |> adapter.rollback_to_savepoint()
      |> adapter.query()
    sandbox_query(restart_query, opts, s)
  end

  defp sandbox_rollback(s, opts) do
    case transaction_handle(s, :handle_rollback, opts, :run) do
      {:ok, s} ->
        {:ok, %Result{value: :ok}, s}
      other ->
        other
    end
  end

  def sandbox_transaction(s, callback, opts, new_status) do
    %{adapter: adapter} = s
    query =
      apply(adapter, callback, ["ecto_sandbox_transaction"])
      |> adapter.query()
    case sandbox_query(query, opts, s) do
      {:ok, _, s} ->
        {:ok, %{s | status: new_status}}
      {:error, err, s} ->
        {:error, err, %{s | status: :sandbox}}
      other ->
        other
    end
  end

  defp sandbox_query(query, opts, s, error \\ :error) do
    query = DBConnection.Query.parse(query, opts)
    case handle_prepare(query, opts, s) do
      {:ok, query, s} ->
        query = DBConnection.Query.describe(query, opts)
        sandbox_execute(query, opts, s, error)
      other ->
        other
    end
  end

  def sandbox_execute(query, opts, s, error) do
    params = DBConnection.Query.encode(query, [], opts)
    case handle_execute_close(query, params, opts, s) do
      {:prepare, s} ->
        err = RuntimeError.exception("query #{inspect query} was not prepared")
        {:error, err, s}
      {:ok, _, s} ->
        {:ok, %Result{value: :ok}, s}
      {:error, err, s} when error == :disconnect ->
        {:disconnect, err, s}
      other ->
        other
    end
  end

end

defimpl String.Chars, for: DBConnection.Query do
  def to_string(%{request: :begin}) do
    "BEGIN SANDBOX"
  end
  def to_string(%{request: :restart}) do
    "RESTART SANDBOX"
  end
  def to_string(%{request: :rollback}) do
    "ROLLBACK SANDBOX"
  end
  def to_string(%{request: :mode}) do
    "SANDBOX MODE"
  end
end

defimpl DBConnection.Query, for: Ecto.Adapters.SQL.Sandbox.Query do
  def parse(query, _), do: query
  def describe(query, _), do: query
  def encode(_ , [], _), do: []
  def decode(_, %Ecto.Adapters.SQL.Sandbox.Result{value: value}, _), do: value
end
