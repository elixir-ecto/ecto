defmodule Mix.Tasks.Ecto.CreateTest do
  use ExUnit.Case, async: true

  import Mix.Tasks.Ecto.Create, only: [run: 1]

  # Mocked adapters

  defmodule Adapter do
    defmacro __using__(_), do: :ok
    def storage_up(_), do: :ok
  end

  defmodule AlreadyUpAdapter do
    defmacro __using__(_), do: :ok
    def storage_up(_), do: {:error, :already_up}
  end

  defmodule ConfusedAdapter do
    defmacro __using__(_), do: :ok
    def storage_up(_), do: {:error, :confused}
  end

  defmodule NoStorageUpAdapter do
    defmacro __using__(_), do: :ok
  end

  #Mocked repos

  defmodule Repo do
    use Ecto.Repo, adapter: Adapter
    def conf, do: parse_url "ecto://user:pass@localhost/repo"
  end

  defmodule ExistingRepo do
    use Ecto.Repo, adapter: AlreadyUpAdapter
    def conf, do: parse_url "ecto://user:pass@localhost/repo"
  end

  defmodule ConfusedRepo do
    use Ecto.Repo, adapter: ConfusedAdapter
    def conf, do: parse_url "ecto://user:pass@localhost/confused"
  end

  defmodule NoStorageUpRepo do
    use Ecto.Repo, adapter: NoStorageUpAdapter
    def conf, do: parse_url "ecto://user:pass@localhost/repo"
  end

  test "runs the adapter storage_up" do
    run [to_string(Repo)]
    assert_received {:mix_shell, :info, ["The database for repo Mix.Tasks.Ecto.CreateTest.Repo has been created."]}
  end

  test "informs the user when the repo is already up" do
    run [to_string(ExistingRepo)]
    assert_received {:mix_shell, :info, ["The database for repo Mix.Tasks.Ecto.CreateTest.ExistingRepo has already been created."]}
  end

  test "raises an error when storage_up gives an unknown feedback" do
    assert_raise Mix.Error, fn -> run [to_string(ConfusedRepo)] end
  end

  test "raises an error when the adapter doesn't define a storage_up" do
    assert_raise Mix.Error, ~r/to define storage_up\/1/, fn -> run [to_string(NoStorageUpRepo)] end
  end
end
