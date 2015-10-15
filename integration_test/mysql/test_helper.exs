Logger.configure(level: :info)

# :uses_usec, :uses_msec and :modify_column are supported
# on MySQL 5.6 but that is not yet supported in travis.
ExUnit.start exclude: [:array_type, :read_after_writes, :uses_usec, :uses_msec,
                       :strict_savepoint, :create_index_if_not_exists, :modify_column]

# Configure Ecto for support and tests
Application.put_env(:ecto, :lock_for_update, "FOR UPDATE")
Application.put_env(:ecto, :primary_key_type, :id)

# Load support files
Code.require_file "../support/repo.exs", __DIR__
Code.require_file "../support/models.exs", __DIR__
Code.require_file "../support/migration.exs", __DIR__

pool =
  case System.get_env("ECTO_POOL") || "poolboy" do
    "poolboy"        -> Ecto.Pools.Poolboy
    "sojourn_broker" -> Ecto.Pools.SojournBroker
  end

# Basic test repo
alias Ecto.Integration.TestRepo

Application.put_env(:ecto, TestRepo,
  adapter: Ecto.Adapters.MySQL,
  url: "ecto://root@localhost/ecto_test",
  pool: Ecto.Pools.Ownership.Server,
  ownership_pool: pool)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo, otp_app: :ecto
end

# Pool repo for transaction and lock tests
alias Ecto.Integration.PoolRepo

Application.put_env(:ecto, PoolRepo,
  adapter: Ecto.Adapters.MySQL,
  pool: pool,
  url: "ecto://root@localhost/ecto_test",
  pool_size: 10)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo, otp_app: :ecto
end

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  setup do
    Ecto.Pools.Ownership.Server.ownership_checkout(TestRepo.Pool,
                                                   Ecto.Adapters.SQL.Sandbox)
    :ok
  end
end

# Load up the repository, start it, and run migrations
_   = Ecto.Storage.down(TestRepo)
:ok = Ecto.Storage.up(TestRepo)

{:ok, _pid} = TestRepo.start_link
{:ok, _pid} = PoolRepo.start_link

Ecto.Pools.Ownership.Server.ownership_checkout(TestRepo.Pool)

:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
Process.flag(:trap_exit, true)

Ecto.Pools.Ownership.Server.ownership_checkin(TestRepo.Pool)
