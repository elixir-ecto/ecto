defmodule Ecto.Adapter.TestTransactions  do
  @moduledoc ~S"""
  Specifies the adapter test transactions API.

  These adapter functions work by starting a transaction and storing
  the connection back in the pool with an open transaction. At the end
  of the test, the transaction is rolled back, reverting all data added
  during tests.

  Note this approach only works if the connection pool has size of 1
  and does not support any overflow.

  ## Postgres example

  The first step is to configure your database pool to have size of
  1 and no max overflow. You set those options in your `config/config.exs`:

      config :my_app, Repo,
        size: 1,
        max_overflow: 0

  Since you don't want those options in your production database, we
  typically recommend to create a `config/test.exs` and add the following
  to the bottom of your `config/config.exs` file:

      import_config "config/#{Mix.env}.exs"

  Now with the test database properly configured, you can write transactional
  tests:

      # All tests in this module will be wrapped in transactions
      defmodule PostTest do
        # Tests that use the shared repository cannot be async
        use ExUnit.Case
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
