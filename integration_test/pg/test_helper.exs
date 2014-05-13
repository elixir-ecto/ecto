ExUnit.start

Code.require_file "../../test/support/file_helpers.exs", __DIR__

alias Ecto.Adapters.Postgres
alias Ecto.Integration.Postgres.TestRepo

defmodule Ecto.Integration.Postgres.CustomAPI do
  use Ecto.Query.Typespec

  deft integer
  defs custom(integer) :: integer
end

defmodule Ecto.Integration.Postgres.TestRepo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres

  def priv do
    "integration_test/pg/ecto/priv"
  end

  def conf do
    parse_url "ecto://postgres:postgres@localhost/ecto_test?size=1&max_overflow=0"
  end

  def query_apis do
    [Ecto.Integration.Postgres.CustomAPI, Ecto.Query.API]
  end
end

defmodule Ecto.Integration.Postgres.Post do
  use Ecto.Model

  schema "posts" do
    field :title, :string
    field :text, :string
    field :tags, { :array, :string }
    field :bin, :binary
    field :temp, :virtual, default: "temp"
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
    field :interval, :interval
    field :bytes, :binary
    belongs_to :post, Ecto.Integration.Postgres.Post
    belongs_to :author, Ecto.Integration.Postgres.User
  end
end

defmodule Ecto.Integration.Postgres.Permalink do
  use Ecto.Model

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

  schema "customs", primary_key: false do
    field :foo, :string, primary_key: true
  end
end

defmodule Ecto.Integration.Postgres.Barebone do
  use Ecto.Model

  schema "barebones", primary_key: false do
    field :text, :string
  end
end

defmodule Ecto.Integration.Postgres.AssignedPrimaryKey do
  use Ecto.Model
  @schema_defaults [primary_key: {:id, :string, []}]
  
  schema "assigned_primary_keys" do
    has_one  :user,  Ecto.Integration.Postgres.User
    has_many :users, Ecto.Integration.Postgres.User
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
      alias Ecto.Integration.Postgres.AssignedPrimaryKey
    end
  end

  setup do
    :ok = Postgres.begin_test_transaction(TestRepo, [])
  end

  teardown do
    :ok = Postgres.rollback_test_transaction(TestRepo, [])
  end
end

setup_cmds = [
  ~s(psql -U postgres -c "DROP DATABASE IF EXISTS ecto_test;"),
  ~s(psql -U postgres -c "CREATE DATABASE ecto_test TEMPLATE=template0 ENCODING='UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8';")
]

Enum.each(setup_cmds, fn(cmd) ->
  key = :ecto_setup_cmd_output
  Process.put(key, "")
  status = Mix.Shell.cmd(cmd, fn(data) ->
    current = Process.get(key)
    Process.put(key, current <> data)
  end)

  if status != 0 do
    IO.puts """
    Test setup command error'd:

        #{cmd}

    With:

        #{Process.get(key)}
    Please verify the user "postgres" exists and it has permissions
    to create databases. If not, you can create a new user with:

        createuser postgres --no-password -d
    """
    System.halt(1)
  end
end)

setup_database = [
  "CREATE TABLE posts (id serial PRIMARY KEY, title varchar(100), text varchar(100), tags text[], bin bytea)",
  "CREATE TABLE comments (id serial PRIMARY KEY, text varchar(100), posted timestamp, day date, time time, interval interval, bytes bytea, post_id integer, author_id integer)",
  "CREATE TABLE permalinks (id serial PRIMARY KEY, url varchar(100), post_id integer)",
  "CREATE TABLE users (id serial PRIMARY KEY, name text)",
  "CREATE TABLE customs (foo text PRIMARY KEY)",
  "CREATE TABLE barebones (text text)",
  "CREATE TABLE assigned_primary_keys (id text PRIMARY KEY, user_id integer)",
  "CREATE TABLE transaction (id serial, text text)",
  "CREATE TABLE lock_counters (id serial PRIMARY KEY, count integer)",
  "CREATE FUNCTION custom(integer) RETURNS integer AS 'SELECT $1 * 10;' LANGUAGE SQL"
]

{ :ok, _pid } = TestRepo.start_link

Enum.each(setup_database, fn(sql) ->
  result = Postgres.query(TestRepo, sql, [])
  if match?({ :error, _ }, result) do
    IO.puts("Test database setup SQL error'd: `#{sql}`")
    IO.inspect(result)
    System.halt(1)
  end
end)
