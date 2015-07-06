Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.PoolTest do
  use Ecto.Integration.Case

  require Ecto.Integration.TestRepo, as: TestRepo

  defmodule MockPool do
    def start_link(_conn_mod, opts) do
      # Custom options are passed through
      assert TestRepo.Alternative == opts[:name]
      assert :bar == opts[:foo]
      {:ok, MockPool}
    end
  end

  test "can start multiple repos" do
    # Can't start a second Repo with the default name
    assert {:error, {:already_started, _}} = TestRepo.start_link()

    # Can start a second repo with a different name
    assert {:ok, _second_pool} = TestRepo.start_link(name: TestRepo.Named)

    # Can start a third repo with a different name and different pool
    assert {:ok, MockPool} =
      TestRepo.start_link(name: TestRepo.Alternative, pool: MockPool, foo: :bar)
  end
end
