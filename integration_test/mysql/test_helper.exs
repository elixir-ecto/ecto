Logger.configure(level: :info)

# :uses_usec, :uses_msec and :modify_column are supported
# on MySQL 5.6 but that is not yet supported in travis.
ExUnit.start exclude: [:array_type, :read_after_writes, :uses_usec, :uses_msec,
                       :strict_savepoint, :create_index_if_not_exists, :modify_column]

# Configure Ecto for support and tests
Application.put_env(:ecto, :lock_for_update, "FOR UPDATE")
Application.put_env(:ecto, :primary_key_type, :id)

# Configure MySQL connection
Application.put_env(:ecto, :mysql_test_url,
  "ecto://" <> (System.get_env("MYSQL_URL") || "root@localhost")
)

# Load support files
Code.require_file "../support/repo.exs", __DIR__
Code.require_file "../support/schemas.exs", __DIR__
Code.require_file "../support/migration.exs", __DIR__

pool =
  case System.get_env("ECTO_POOL") || "poolboy" do
    "poolboy"        -> DBConnection.Poolboy
    "sojourn_broker" -> DBConnection.SojournBroker
  end

# Basic test repo
alias Ecto.Integration.TestRepo

Application.put_env(:ecto, TestRepo,
  adapter: Ecto.Adapters.MySQL,
  url: Application.get_env(:ecto, :mysql_test_url) <> "/ecto_test",
  pool: Ecto.Adapters.SQL.Sandbox)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo, otp_app: :ecto

  def create_prefix(prefix) do
    "create database #{prefix}"
  end

  def drop_prefix(prefix) do
    "drop database #{prefix}"
  end
end

# Pool repo for transaction and lock tests
alias Ecto.Integration.PoolRepo

Application.put_env(:ecto, PoolRepo,
  adapter: Ecto.Adapters.MySQL,
  pool: pool,
  url: Application.get_env(:ecto, :mysql_test_url) <> "/ecto_test",
  pool_size: 10)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo, otp_app: :ecto
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

# Load up the repository, start it, and run migrations
_   = Ecto.Storage.down(TestRepo)
:ok = Ecto.Storage.up(TestRepo)

{:ok, _pid} = TestRepo.start_link
{:ok, _pid} = PoolRepo.start_link

:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
Process.flag(:trap_exit, true)
