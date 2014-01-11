defmodule Mix.Tasks.Ecto.DropTest do
  use ExUnit.Case, async: true

  import Mix.Tasks.Ecto.Drop, only: [run: 1]

  # Mocked adapters

  defmodule Adapter do
    defmacro __using__(_), do: :ok
    def storage_down(_), do: :ok
  end

  defmodule AlreadyDownAdapter do
    defmacro __using__(_), do: :ok
    def storage_down(_), do: { :error, :already_down }
  end

  defmodule ConfusedAdapter do
    defmacro __using__(_), do: :ok
    def storage_down(_), do: { :error, :confused }
  end

  defmodule NoStorageDownAdapter do
    defmacro __using__(_), do: :ok
  end

  # Mocked repos 

  defmodule Repo do
    use Ecto.Repo, adapter: Adapter
    def url, do: "ecto://user:pass@localhost/repo"
  end

  defmodule ExistingRepo do
    use Ecto.Repo, adapter: AlreadyDownAdapter
    def url, do: "ecto://user:pass@localhost/repo"
  end

  defmodule ConfusedRepo do
    use Ecto.Repo, adapter: ConfusedAdapter
    def url, do: "ecto://user:pass@localhost/confused"
  end

  defmodule NoStorageDownRepo do
    use Ecto.Repo, adapter: NoStorageDownAdapter
    def url, do: "ecto://user:pass@localhost/repo"
  end

  test "runs the adapter storage_down" do
    run [to_string(Repo)]
    assert_received { :mix_shell, :info, ["The database for repo Mix.Tasks.Ecto.DropTest.Repo has been dropped."] }
  end

  test "informs the user when the repo is already down" do
    run [to_string(ExistingRepo)]
    assert_received { :mix_shell, :info, ["The database for repo Mix.Tasks.Ecto.DropTest.ExistingRepo has already been dropped."] }
  end

  test "raises an error when storage_down gives an unknown feedback" do
    assert_raise Mix.Error, fn -> run [to_string(ConfusedRepo)] end
  end

  test "raises an error when the adapter doesn't define a storage_down" do
    assert_raise Mix.Error, %r/to define storage_down\/1/, fn -> run [to_string(NoStorageDownRepo)] end
  end
end
