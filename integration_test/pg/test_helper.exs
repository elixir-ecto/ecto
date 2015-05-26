Logger.configure(level: :info)
ExUnit.start

Code.require_file "../support/repo.exs", __DIR__

# Basic test repo
alias Ecto.Integration.TestRepo

Application.put_env(:ecto, TestRepo,
  adapter: Ecto.Adapters.Postgres,
  url: "ecto://postgres:postgres@localhost/ecto_test",
  size: 1,
  max_overflow: 0)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo, otp_app: :ecto
end

# Pool repo for transaction and lock tests
alias Ecto.Integration.PoolRepo

Application.put_env(:ecto, PoolRepo,
  adapter: Ecto.Adapters.Postgres,
  url: "ecto://postgres:postgres@localhost/ecto_test",
  size: 10)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo, otp_app: :ecto

  def lock_for_update, do: "FOR UPDATE"
end

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  setup_all do
    Ecto.Adapters.SQL.begin_test_transaction(TestRepo, [])
    on_exit fn -> Ecto.Adapters.SQL.rollback_test_transaction(TestRepo, []) end
    :ok
  end

  setup do
    Ecto.Adapters.SQL.restart_test_transaction(TestRepo, [])
    :ok
  end
end

# Load support models and migration
Code.require_file "../support/models.exs", __DIR__
Code.require_file "../support/migration.exs", __DIR__

# Load up the repository, start it, and run migrations
_   = Ecto.Storage.down(TestRepo)
:ok = Ecto.Storage.up(TestRepo)

{:ok, _pid} = TestRepo.start_link
{:ok, _pid} = PoolRepo.start_link

:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
