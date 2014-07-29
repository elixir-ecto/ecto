defmodule Ecto.Adapter.TestTransactions  do
  @moduledoc """
  Specifies the adapter test transactions API.

  These adapter functions work by starting a transaction and storing
  the connection back in the pool with an open transaction. At the end
  of the test, the transaction is rolled back, reverting all data added
  during tests.

  Note this approach only works if the connection pool has size of 1
  and does not support any overflow.

  ## Postgres test example

      defmodule TestRepo do
        use Ecto.Repo, adapter: Ecto.Adapters.Postgres

        # When testing it is important to set `size=1&max_overflow=0` so that
        # the repo will only have one connection
        def conf do
          parse_url "ecto://postgres:postgres@localhost/test?size=1&max_overflow=0"
        end
      end

      # All tests in this module will be wrapped in transactions
      defmodule PostTest do
        # Tests that use the shared repository should be sync
        use ExUnit.Case, async: false
        alias Ecto.Adapters.Postgres

        setup do
          Postgres.begin_test_transaction(TestRepo)

          on_exit fn ->
            Postgres.rollback_test_transaction(TestRepo)
          end
        end

        test "create comment" do
          assert %Post{} = TestRepo.insert(%Post{})
        end
      end
  """

  use Behaviour

  @doc """
  Starts a test transaction, see example above for usage.
  """
  defcallback begin_test_transaction(Ecto.Repo.t, Keyword.t) :: :ok | no_return

  @doc """
  Ends a test transaction, see example above for usage.
  """
  defcallback rollback_test_transaction(Ecto.Repo.t, Keyword.t) :: :ok | no_return
end
