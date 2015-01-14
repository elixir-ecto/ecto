Logger.configure(level: :info)
Code.require_file "../../test/support/file_helpers.exs", __DIR__
Code.require_file "../../test/support/types.exs", __DIR__

ExUnit.start

alias Ecto.Adapters.Postgres
alias Ecto.Integration.Postgres.TestRepo

Application.put_env(:ecto, TestRepo,
  url: "ecto://postgres:postgres@localhost/ecto_test",
  size: 1,
  max_overflow: 0)

defmodule Ecto.Integration.Postgres.TestRepo do
  use Ecto.Repo,
    otp_app: :ecto,
    adapter: Ecto.Adapters.Postgres
end

defmodule Ecto.Integration.Postgres.Post do
  use Ecto.Model

  schema "posts" do
    field :title, :string
    field :counter, :integer, read_after_writes: true
    field :text, :string
    field :tags, {:array, :string}
    field :bin, :binary
    field :uuid, :uuid
    field :temp, :string, default: "temp", virtual: true
    has_many :comments, Ecto.Integration.Postgres.Comment
    has_one :permalink, Ecto.Integration.Postgres.Permalink
  end
end

defmodule Ecto.Integration.Postgres.Comment do
  use Ecto.Model

  schema "comments" do
    field :text, :string
    field :posted, :datetime
    field :day, :date
    field :time, :time
    field :bytes, :binary
    belongs_to :post, Ecto.Integration.Postgres.Post
    belongs_to :author, Ecto.Integration.Postgres.User
  end
end

defmodule Ecto.Integration.Postgres.Permalink do
  use Ecto.Model

  @foreign_key_type Custom.Permalink
  schema "permalinks" do
    field :url, :string
    belongs_to :post, Ecto.Integration.Postgres.Post
  end
end

defmodule Ecto.Integration.Postgres.User do
  use Ecto.Model

  schema "users" do
    field :name, :string
    has_many :comments, Ecto.Integration.Postgres.Comment
  end
end

defmodule Ecto.Integration.Postgres.Custom do
  use Ecto.Model

  @primary_key {:foo, :uuid, []}
  schema "customs" do
  end
end

defmodule Ecto.Integration.Postgres.Barebone do
  use Ecto.Model

  @primary_key false
  schema "barebones" do
    field :text, :string
  end
end

defmodule Ecto.Integration.Postgres.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__)
      require TestRepo

      import Ecto.Query
      alias Ecto.Integration.Postgres.TestRepo
      alias Ecto.Integration.Postgres.Post
      alias Ecto.Integration.Postgres.Comment
      alias Ecto.Integration.Postgres.Permalink
      alias Ecto.Integration.Postgres.User
      alias Ecto.Integration.Postgres.Custom
      alias Ecto.Integration.Postgres.Barebone
    end
  end

  setup do
    :ok = Postgres.begin_test_transaction(TestRepo, [])

    on_exit fn ->
      :ok = Postgres.rollback_test_transaction(TestRepo, [])
    end

    :ok
  end
end

Ecto.Storage.down(TestRepo)
Ecto.Storage.up(TestRepo)

{:ok, _pid} = TestRepo.start_link

defmodule Ecto.Integration.Migration do
  use Ecto.Migration

  def up do
    create table(:posts) do
      add :title, :string, size: 100
      add :counter, :integer, default: 10
      add :text, :string
      add :tags, {:array, :text}
      add :bin, :binary
      add :uuid, :uuid
      add :cost, :decimal, precision: 2, scale: 2
    end

    create table(:users) do
      add :name, :text
    end

    create table(:permalinks) do
      add :url
      add :post_id, :integer
    end

    create table(:comments) do
      add :text, :string, size: 100
      add :posted, :datetime
      add :day, :date
      add :time, :time
      add :bytes, :binary
      add :post_id, references(:posts)
      add :author_id, references(:users)
    end

    create table(:customs, primary_key: false) do
      add :foo, :uuid, primary_key: true
    end

    create table(:barebones) do
      add :text, :text
    end

    create table(:transactions) do
      add :text, :text
    end

    create table(:lock_counters) do
      add :count, :integer
    end
  end
end

Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration)
