defmodule Mix.Tasks.Ecto.CreateTest do
  use ExUnit.Case, async: true

  import Mix.Tasks.Ecto.Create, only: [run: 1]

  defmodule Adapter do 
    defmacro __using__(_), do: :ok
    def storage_up(_), do: :ok
  end

  defmodule Repo do
    use Ecto.Repo, adapter: Adapter
    def url, do: "ecto://user:pass@localhost/repo"
  end

  defmodule AlreadyUpAdapter do 
    defmacro __using__(_), do: :ok
    def storage_up(_), do: { :error, :already_up }
  end

  defmodule ExistingRepo do 
    use Ecto.Repo, adapter: AlreadyUpAdapter
    def url, do: "ecto://user:pass@localhost/repo"
  end

  defmodule ConfusedAdapter do 
    defmacro __using__(_), do: :ok
    def storage_up(_), do: { :error, :confused }
  end

  defmodule ConfusedRepo do 
    use Ecto.Repo, adapter: ConfusedAdapter
    def url, do: "ecto://user:pass@localhost/confused"
  end

  test "runs the adapter storage_up" do
    run [to_string(Repo)] 
    assert_received { :mix_shell, :info, ["The repo Mix.Tasks.Ecto.CreateTest.Repo has been created."] }
  end

  test "informs the user when the repo is already up" do 
    run [to_string(ExistingRepo)]
    assert_received { :mix_shell, :info, ["The repo Mix.Tasks.Ecto.CreateTest.ExistingRepo is already up."] }
  end

  test "raises an error when storage_up gives an unknown feedback" do 
    assert_raise Mix.Error, fn -> run [to_string(ConfusedRepo)] end
  end
end
