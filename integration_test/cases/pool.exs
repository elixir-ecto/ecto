Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.PoolTest do
  use Ecto.Integration.Case

  require Ecto.Integration.PoolRepo, as: PoolRepo

  defmodule MockPool do
    def start_link(_conn_mod, opts) do
      # Custom options are passed through
      assert PoolRepo.Third == opts[:name]
      assert :bar == opts[:foo]
      {:ok, MockPool}
    end
  end

  test "can start multiple repos" do
    # Can't start a second Repo with the default name
    assert {:error, {:already_started, _}} = PoolRepo.start_link()

    # Can start a second repo with a different name
    assert {:ok, _second_pool} = PoolRepo.start_link(name: PoolRepo.Second)

    # Can start a third repo with a different name and different pool
    assert {:ok, MockPool} =
      PoolRepo.start_link(name: PoolRepo.Third, pool: MockPool, foo: :bar)
  end
end
