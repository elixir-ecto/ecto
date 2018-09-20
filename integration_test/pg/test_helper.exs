Logger.configure(level: :info)
ExUnit.start

# Configure Ecto for support and tests
Application.put_env(:ecto, :lock_for_update, "FOR UPDATE")
Application.put_env(:ecto, :primary_key_type, :id)

# Configure PG connection
Application.put_env(:ecto, :pg_test_url,
  "ecto://" <> (System.get_env("PG_URL") || "postgres:postgres@localhost")
)

# Load support files
Code.require_file "../support/repo.exs", __DIR__
Code.require_file "../support/schemas.exs", __DIR__
Code.require_file "../support/migration.exs", __DIR__

pool =
  case System.get_env("ECTO_POOL") || "poolboy" do
    "poolboy" -> DBConnection.Poolboy
    "sbroker" -> DBConnection.Sojourn
  end

# Pool repo for async, safe tests
alias Ecto.Integration.TestRepo

Application.put_env(:ecto, TestRepo,
  adapter: Ecto.Adapters.Postgres,
  url: Application.get_env(:ecto, :pg_test_url) <> "/ecto_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  ownership_pool: pool)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo, otp_app: :ecto
end

# Pool repo for non-async tests
alias Ecto.Integration.PoolRepo

Application.put_env(:ecto, PoolRepo,
  adapter: Ecto.Adapters.Postgres,
  pool: pool,
  url: Application.get_env(:ecto, :pg_test_url) <> "/ecto_test",
  pool_size: 10,
  max_restarts: 20,
  max_seconds: 10)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo, otp_app: :ecto

  def create_prefix(prefix) do
    "create schema #{prefix}"
  end

  def drop_prefix(prefix) do
    "drop schema #{prefix}"
  end
end

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
  end
end

{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(TestRepo, :temporary)

# Load up the repository, start it, and run migrations
_   = Ecto.Adapters.Postgres.storage_down(TestRepo.config)
:ok = Ecto.Adapters.Postgres.storage_up(TestRepo.config)

{:ok, _pid} = TestRepo.start_link
{:ok, _pid} = PoolRepo.start_link

%{rows: [[version]]} = TestRepo.query!("SHOW server_version", [])

version =
  case Regex.named_captures(~r/(?<major>[0-9]*)(\.(?<minor>[0-9]*))?.*/, version) do
    %{"major" => major, "minor" => minor} -> "#{major}.#{minor}.0"
    %{"major" => major} -> "#{major}.0.0"
    _other -> version
  end

if Version.match?(version, ">= 9.5.0") do
  ExUnit.configure(exclude: [:without_conflict_target])
else
  Application.put_env(:ecto, :postgres_map_type, "json")
  ExUnit.configure(exclude: [:upsert, :upsert_all, :array_type])
end

:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)
