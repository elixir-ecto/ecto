defmodule Mix.Tasks.Ecto.CreateDropTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Ecto.Create
  alias Mix.Tasks.Ecto.Drop

  # Mocked adapters

  defmodule Adapter do
    @behaviour Ecto.Adapter.Storage
    defmacro __before_compile__(_), do: :ok
    def storage_up(_), do: Process.get(:storage_up) || raise "no storage_up"
    def storage_down(_), do: Process.get(:storage_down) || raise "no storage_down"
  end

  defmodule NoStorageAdapter do
    defmacro __before_compile__(_), do: :ok
  end

  # Mocked repos

  defmodule Repo do
    use Ecto.Repo, otp_app: :ecto, adapter: Adapter
  end

  defmodule NoStorageRepo do
    use Ecto.Repo, otp_app: :ecto, adapter: NoStorageAdapter
  end

  setup do
    opts = [disable_safety_warnings: true]
    Application.put_env(:ecto, __MODULE__.Repo, opts)
    Application.put_env(:ecto, __MODULE__.NoStorageRepo, opts)
  end

  ## Create

  test "runs the adapter storage_up" do
    Process.put(:storage_up, :ok)
    Create.run ["-r", to_string(Repo)]
    assert_received {:mix_shell, :info, ["The database for Mix.Tasks.Ecto.CreateDropTest.Repo has been created."]}
  end

  test "runs the adapter storage_up with --quiet" do
    Process.put(:storage_up, :ok)
    Create.run ["-r", to_string(Repo), "--quiet"]
    refute_received {:mix_shell, :info, [_]}
  end

  test "informs the user when the repo is already up" do
    Process.put(:storage_up, {:error, :already_up})
    Create.run ["-r", to_string(Repo)]
    assert_received {:mix_shell, :info, ["The database for Mix.Tasks.Ecto.CreateDropTest.Repo has already been created."]}
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
    assert_received {:mix_shell, :info, ["The database for Mix.Tasks.Ecto.CreateDropTest.Repo has been dropped."]}
  end

  test "runs the adapter storage_down with --quiet" do
    Process.put(:storage_down, :ok)
    Drop.run ["-r", to_string(Repo), "--quiet"]
    refute_received {:mix_shell, :info, [_]}
  end

  test "informs the user when the repo is already down" do
    Process.put(:storage_down, {:error, :already_down})
    Drop.run ["-r", to_string(Repo)]
    assert_received {:mix_shell, :info, ["The database for Mix.Tasks.Ecto.CreateDropTest.Repo has already been dropped."]}
  end

  test "raises an error when storage_down gives an unknown feedback" do
    Process.put(:storage_down, {:error, :confused})
    assert_raise Mix.Error, fn ->
      Drop.run ["-r", to_string(Repo)]
    end
  end

  test "raises an error on storage_down when the adapter doesn't define a storage" do
    assert_raise Mix.Error, ~r/to implement Ecto.Adapter.Storage/, fn ->
      Drop.run ["-r", to_string(NoStorageRepo)]
    end
  end
end
