Logger.configure(level: :error)
ExUnit.start exclude: [:assigns_primary_key, :array_type, :case_sensitive]
require Logger
# Basic test repo
alias Ecto.Integration.TestRepo

Application.put_env(:ecto, TestRepo,
  url: "ecto://mssql:mssql@mssql.local/ecto_test",
  size: 1,
  max_overflow: 0)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Repo,
    otp_app: :ecto,
    adapter: Ecto.Adapters.Mssql
end

# Pool repo for transaction and lock tests
alias Ecto.Integration.PoolRepo

Application.put_env(:ecto, PoolRepo,
  url: "ecto://mssql:mssql@mssql.local/ecto_test",
  size: 10)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Repo,
    otp_app: :ecto,
    adapter: Ecto.Adapters.Mssql

    def lock_for_update, do: "WITH(UPDLOCK)"
end

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__)
      require TestRepo

      import Ecto.Query
      alias Ecto.Integration.TestRepo
      alias Ecto.Integration.Post
      alias Ecto.Integration.Comment
      alias Ecto.Integration.Permalink
      alias Ecto.Integration.User
      alias Ecto.Integration.Custom
      alias Ecto.Integration.Barebone
    end
  end

  setup_all do
    Ecto.Adapters.SQL.begin_test_transaction(TestRepo, [])
    on_exit fn -> Ecto.Adapters.SQL.rollback_test_transaction(TestRepo, []) end
    :ok
  end

  setup do
    #Ecto.Adapters.SQL.begin_test_transaction(TestRepo, [])
    Ecto.Adapters.SQL.restart_test_transaction(TestRepo, [])
    #on_exit fn -> Ecto.Adapters.SQL.rollback_test_transaction(TestRepo, []) end
    :ok 
  end
end
:erlang.system_flag :backtrace_depth, 50
# Load support models and migration
Code.require_file "../support/models.exs", __DIR__
Code.require_file "../support/migration.exs", __DIR__

# Load up the repository, start it, and run migrations
_   = Ecto.Storage.down(TestRepo)
:ok = Ecto.Storage.up(TestRepo)

{:ok, _pid} = TestRepo.start_link
{:ok, _pid} = PoolRepo.start_link

:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
