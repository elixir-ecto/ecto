Logger.configure(level: :info)

# :modify_column is supported on MySQL 5.7
# but that is not yet supported in travis.
ExUnit.start exclude: [:array_type, :read_after_writes, :returning, :modify_column,
                       :strict_savepoint, :create_index_if_not_exists, :aggregate_filters,
                       :transaction_isolation, :rename_column, :with_conflict_target]

# Configure Ecto for support and tests
Application.put_env(:ecto, :lock_for_update, "FOR UPDATE")
Application.put_env(:ecto, :primary_key_type, :id)
Application.put_env(:ecto, :async_integration_tests, false)

# Configure MySQL connection
Application.put_env(:ecto, :mysql_test_url,
  "ecto://" <> (System.get_env("MYSQL_URL") || "root@localhost")
)

# Load support files
Code.require_file "../support/repo.exs", __DIR__
Code.require_file "../support/schemas.exs", __DIR__
Code.require_file "../support/migration.exs", __DIR__

# Pool repo for async, safe tests
alias Ecto.Integration.TestRepo

Application.put_env(:ecto, TestRepo,
  url: Application.get_env(:ecto, :mysql_test_url) <> "/ecto_test",
  pool: Ecto.Adapters.SQL.Sandbox)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo, otp_app: :ecto, adapter: Ecto.Adapters.MySQL
end

# Pool repo for non-async tests
alias Ecto.Integration.PoolRepo

Application.put_env(:ecto, PoolRepo,
  adapter: Ecto.Adapters.MySQL,
  url: Application.get_env(:ecto, :mysql_test_url) <> "/ecto_test",
  pool_size: 10)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo, otp_app: :ecto, adapter: Ecto.Adapters.MySQL

  def create_prefix(prefix) do
    "create database #{prefix}"
  end

  def drop_prefix(prefix) do
    "drop database #{prefix}"
  end
end

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
  end
end

{:ok, _} = Ecto.Adapters.MySQL.ensure_all_started(TestRepo.config(), :temporary)

# Load up the repository, start it, and run migrations
_   = Ecto.Adapters.MySQL.storage_down(TestRepo.config)
:ok = Ecto.Adapters.MySQL.storage_up(TestRepo.config)

{:ok, _pid} = TestRepo.start_link
{:ok, _pid} = PoolRepo.start_link
:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)
