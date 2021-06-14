defmodule Mix.Tasks.Ecto.CreateDropTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Ecto.{Create, Drop}

  # Mocked adapters

  defmodule Adapter do
    @behaviour Ecto.Adapter
    @behaviour Ecto.Adapter.Storage

    defmacro __before_compile__(_), do: :ok
    def dumpers(_, _), do: raise "not implemented"
    def loaders(_, _), do: raise "not implemented"
    def init(_), do: raise "not implemented"
    def checkout(_, _, _), do: raise "not implemented"
    def checked_out?(_), do: raise "not implemented"
    def ensure_all_started(_, _), do: raise "not implemented"

    def storage_up(_), do: Process.get(:storage_up) || raise "no storage_up"
    def storage_down(_), do: Process.get(:storage_down) || raise "no storage_down"
    def storage_status(_), do: raise "no storage_status"
  end

  defmodule NoStorageAdapter do
    @behaviour Ecto.Adapter
    defmacro __before_compile__(_), do: :ok
    def dumpers(_, _), do: raise "not implemented"
    def loaders(_, _), do: raise "not implemented"
    def init(_), do: raise "not implemented"
    def checkout(_, _, _), do: raise "not implemented"
    def checked_out?(_), do: raise "not implemented"
    def ensure_all_started(_, _), do: raise "not implemented"
  end

  # Mocked repos

  defmodule Repo do
    use Ecto.Repo, otp_app: :ecto, adapter: Adapter
  end

  defmodule NoStorageRepo do
    use Ecto.Repo, otp_app: :ecto, adapter: NoStorageAdapter
  end

  setup do
    Application.put_env(:ecto, __MODULE__.Repo, [])
    Application.put_env(:ecto, __MODULE__.NoStorageRepo, [])
  end

  ## Create

  test "runs the adapter storage_up" do
    Process.put(:storage_up, :ok)
    Create.run ["-r", to_string(Repo)]
    assert_received {:mix_shell, :info, ["The database for Mix.Tasks.Ecto.CreateDropTest.Repo has been created"]}
  end

  test "runs the adapter storage_up with --quiet" do
    Process.put(:storage_up, :ok)
    Create.run ["-r", to_string(Repo), "--quiet"]
    refute_received {:mix_shell, :info, [_]}
  end

  test "informs the user when the repo is already up" do
    Process.put(:storage_up, {:error, :already_up})
    Create.run ["-r", to_string(Repo)]
    assert_received {:mix_shell, :info, ["The database for Mix.Tasks.Ecto.CreateDropTest.Repo has already been created"]}
  end

  test "raises an error when storage_up gives an unknown feedback" do
    Process.put(:storage_up, {:error, :confused})
    assert_raise Mix.Error, fn ->
      Create.run ["-r", to_string(Repo)]
    end
  end

  test "raises an error on storage_up when the adapter doesn't define a storage" do
    assert_raise Mix.Error, ~r/to implement Ecto.Adapter.Storage/, fn ->
      Create.run ["-r", to_string(NoStorageRepo)]
    end
  end

  ## Down

  test "runs the adapter storage_down" do
    Process.put(:storage_down, :ok)
    Drop.run ["-r", to_string(Repo)]
    assert_received {:mix_shell, :info, ["The database for Mix.Tasks.Ecto.CreateDropTest.Repo has been dropped"]}
  end

  test "runs the adapter storage_down with --quiet" do
    Process.put(:storage_down, :ok)
    Drop.run ["-r", to_string(Repo), "--quiet"]
    refute_received {:mix_shell, :info, [_]}
  end

  test "informs the user when the repo is already down" do
    Process.put(:storage_down, {:error, :already_down})
    Drop.run ["-r", to_string(Repo)]
    assert_received {:mix_shell, :info, ["The database for Mix.Tasks.Ecto.CreateDropTest.Repo has already been dropped"]}
  end

  test "raises an error when storage_down gives an unknown feedback" do
    Process.put(:storage_down, {:error, {:error, :confused}})
    assert_raise Mix.Error, ~r/couldn't be dropped: {:error, :confused}/, fn ->
      Drop.run ["-r", to_string(Repo)]
    end

    Process.put(:storage_down, {:error, "unknown"})
    assert_raise Mix.Error, ~r/couldn't be dropped: unknown/, fn ->
      Drop.run ["-r", to_string(Repo)]
    end
  end

  test "raises an error on storage_down when the adapter doesn't define a storage" do
    assert_raise Mix.Error, ~r/to implement Ecto.Adapter.Storage/, fn ->
      Drop.run ["-r", to_string(NoStorageRepo)]
    end
  end
end
