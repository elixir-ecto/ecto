defmodule Mix.EctoSQLTest do
  use ExUnit.Case, async: true
  import Mix.EctoSQL

  defmodule Repo do
    def start_link(opts) do
      assert opts[:pool_size] == 2
      Process.get(:start_link)
    end

    def __adapter__ do
      Ecto.TestAdapter
    end

    def config do
      [priv: Process.get(:priv), otp_app: :ecto]
    end
  end

  test "ensure_started" do
    Process.put(:start_link, {:ok, self()})
    assert ensure_started(Repo, []) == {:ok, self(), []}

    Process.put(:start_link, {:error, {:already_started, self()}})
    assert ensure_started(Repo, []) == {:ok, nil, []}

    Process.put(:start_link, {:error, self()})
    assert_raise Mix.Error, fn -> ensure_started(Repo, []) end
  end

  test "source_priv_repo" do
    Process.put(:priv, nil)
    assert source_repo_priv(Repo) == Path.expand("priv/repo", File.cwd!)
    Process.put(:priv, "hello")
    assert source_repo_priv(Repo) == Path.expand("hello", File.cwd!)
  end
end
