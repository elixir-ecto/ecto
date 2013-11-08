defmodule Ecto.Adapter.TestTransactions  do
  @moduledoc """
  Specifies the transactions test API that an adapter is required to implement.
  Should only be used during testing.

  ## Postgres test example

      defmodule TestRepo do
        use Ecto.Repo, adapter: Ecto.Adapters.Postgres

        # When testing it is important to set `size=1&max_overflow=0` so that
        # the repo will only have one connection
        def url do
          "ecto://postgres:postgres@localhost/test?size=1&max_overflow=0"
        end
      end

      # All tests in this module will be wrapped in transactions
      defmodule PostTest do
        # Important to set `async: false` for all tests sharing a repo.
        use ExUnit.Case, async: false
        alias Ecto.Adapters.Postgres

        setup do
          Postgres.begin_test_transaction(TestRepo)
        end

        teardown do
          Postgres.rollback_test_transaction(TestRepo)
        end

        test "create comment" do
          assert Post.Entity[] = TestRepo.create(Post.new)
        end
      end
  """

  use Behaviour

  @doc """
  Starts a test transaction, see example above for usage.
  """
  defcallback begin_test_transaction(Ecto.Repo.t) :: :ok | no_return

  @doc """
  Ends a test transaction, see example above for usage.
  """
  defcallback rollback_test_transaction(Ecto.Repo.t) :: :ok | no_return
end
