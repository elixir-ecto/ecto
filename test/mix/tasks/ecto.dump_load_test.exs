defmodule Mix.Tasks.Ecto.DumpLoadTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Ecto.{Load, Dump}

  # Mocked adapters

  defmodule Adapter do
    @behaviour Ecto.Adapter
    @behaviour Ecto.Adapter.Structure

    defmacro __before_compile__(_), do: :ok
    def dumpers(_, _), do: raise "not implemented"
    def loaders(_, _), do: raise "not implemented"
    def init(_), do: raise "not implemented"
    def ensure_all_started(_, _), do: raise "not implemented"

    def structure_dump(_, _), do: Process.get(:structure_dump) || raise "no structure_dump"
    def structure_load(_, _), do: Process.get(:structure_load) || raise "no structure_load"
  end

  defmodule NoStructureAdapter do
    @behaviour Ecto.Adapter
    defmacro __before_compile__(_), do: :ok
    def dumpers(_, _), do: raise "not implemented"
    def loaders(_, _), do: raise "not implemented"
    def init(_), do: raise "not implemented"
    def ensure_all_started(_, _), do: raise "not implemented"
  end

  # Mocked repos

  defmodule Repo do
    use Ecto.Repo, otp_app: :ecto, adapter: Adapter
  end

  defmodule NoStructureRepo do
    use Ecto.Repo, otp_app: :ecto, adapter: NoStructureAdapter
  end

  setup do
    Application.put_env(:ecto, __MODULE__.Repo, [])
    Application.put_env(:ecto, __MODULE__.NoStructureRepo, [])
  end

  ## Dump

  test "runs the adapter structure_dump" do
    Process.put(:structure_dump, {:ok, "foo"})
    Dump.run ["-r", to_string(Repo)]
    assert_received {:mix_shell, :info, ["The structure for Mix.Tasks.Ecto.DumpLoadTest.Repo has been dumped to foo"]}
  end

  test "runs the adapter structure_dump with --quiet" do
    Process.put(:structure_dump, {:ok, "foo"})
    Dump.run ["-r", to_string(Repo), "--quiet"]
    refute_received {:mix_shell, :info, [_]}
  end

  test "raises an error when structure_dump gives an unknown feedback" do
    Process.put(:structure_dump, {:error, :confused})
    assert_raise Mix.Error, fn ->
      Dump.run ["-r", to_string(Repo)]
    end
  end

  test "raises an error on structure_dump when the adapter doesn't define a storage" do
    assert_raise Mix.Error, ~r/to implement Ecto.Adapter.Structure/, fn ->
      Dump.run ["-r", to_string(NoStructureRepo)]
    end
  end

  ## Load

  test "runs the adapter structure_load" do
    Process.put(:structure_load, {:ok, "foo"})
    Load.run ["-r", to_string(Repo)]
    assert_received {:mix_shell, :info, ["The structure for Mix.Tasks.Ecto.DumpLoadTest.Repo has been loaded from foo"]}
  end

  test "runs the adapter structure_load with --quiet" do
    Process.put(:structure_load, {:ok, "foo"})
    Load.run ["-r", to_string(Repo), "--quiet"]
    refute_received {:mix_shell, :info, [_]}
  end

  test "raises an error when structure_load gives an unknown feedback" do
    Process.put(:structure_load, {:error, :confused})
    assert_raise Mix.Error, fn ->
      Load.run ["-r", to_string(Repo)]
    end
  end

  test "raises an error on structure_load when the adapter doesn't define a storage" do
    assert_raise Mix.Error, ~r/to implement Ecto.Adapter.Structure/, fn ->
      Load.run ["-r", to_string(NoStructureRepo)]
    end
  end
end
