Logger.configure(level: :info)
ExUnit.start

# Basic test repo
alias Ecto.Integration.TestRepo

Application.put_env(:ecto, TestRepo,
  url: "ecto://root@localhost/ecto_test",
  size: 1,
  max_overflow: 0)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Repo,
    otp_app: :ecto,
    adapter: Ecto.Adapters.MySQL
end

# Pool repo for transaction and lock tests
alias Ecto.Integration.PoolRepo

Application.put_env(:ecto, PoolRepo,
  url: "ecto://root@localhost/ecto_test",
  size: 10)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Repo,
    otp_app: :ecto,
    adapter: Ecto.Adapters.MySQL
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

  setup do
    :ok = Ecto.Adapters.SQL.begin_test_transaction(TestRepo, [])

    on_exit fn ->
      :ok = Ecto.Adapters.SQL.rollback_test_transaction(TestRepo, [])
    end

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

_ = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
