ExUnit.start

Code.require_file "../../test/support/file_helpers.exs", __DIR__

alias Ecto.Adapters.Mysql
alias Ecto.Integration.Mysql.TestRepo

defmodule Ecto.Integration.Mysql.CustomAPI do
  use Ecto.Query.Typespec

  deft integer
  defs custom(integer) :: integer
end

defmodule Ecto.Integration.Mysql.TestRepo do
  use Ecto.Repo, adapter: Ecto.Adapters.Mysql

  def priv do
    "integration_test/mysql/ecto/priv"
  end

  def conf do
    parse_url "ecto://mysql:ecto@localhost/ecto_test?size=1&max_overflow=0"
  end

  def query_apis do
    [Ecto.Integration.Mysql.CustomAPI, Ecto.Query.API]
  end
end

defmodule Ecto.Integration.Mysql.Post do
  use Ecto.Model

  queryable "posts" do
    field :title, :string
    field :text, :string
    field :tags, { :array, :string }
    field :bin, :binary
    field :temp, :virtual, default: "temp"
    field :count, :integer
    has_many :comments, Ecto.Integration.Postgres.Comment
    has_one :permalink, Ecto.Integration.Postgres.Permalink
  end
end

defmodule Ecto.Integration.Mysql.Comment do
  use Ecto.Model

  queryable "comments" do
    field :text, :string
    field :posted, :datetime
    field :interval, :interval
    field :bytes, :binary
    belongs_to :post, Ecto.Integration.Mysql.Post
    belongs_to :author, Ecto.Integration.Mysql.User
  end
end

defmodule Ecto.Integration.Mysql.Permalink do
  use Ecto.Model

  queryable "permalinks" do
    field :url, :string
    belongs_to :post, Ecto.Integration.Mysql.Post
  end
end

defmodule Ecto.Integration.Mysql.User do
  use Ecto.Model

  queryable "users" do
    field :name, :string
    has_many :comments, Ecto.Integration.Mysql.Comment
  end
end

defmodule Ecto.Integration.Mysql.Custom do
  use Ecto.Model

  queryable "customs", primary_key: false do
    field :foo, :string, primary_key: true
  end
end

defmodule Ecto.Integration.Mysql.Barebone do
  use Ecto.Model

  queryable "barebones", primary_key: false do
    field :text, :string
  end
end

defmodule Ecto.Integration.Mysql.Case do
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
  end

  teardown do
    :ok = Postgres.rollback_test_transaction(TestRepo, [])
  end
end

setup_cmds = [
  ~s(mysql -u ecto -e "DROP DATABASE IF EXISTS ecto_test;"),
  ~s(mysql -u ecto -e "CREATE DATABASE ecto_test CHARACTER SET utf8 COLLATE utf8_general_ci;")
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
    Please verify the user "ecto" exists and it has permissions
    to create databases. If not, you can create a new user with:

        CREATE USER 'ecto'@'localhost';
        GRANT ALL ON *.* to 'ecto'@'localhost';
    """
    System.halt(1)
  end
end)

setup_database = [
  "CREATE TABLE posts (id serial PRIMARY KEY, title varchar(100), text varchar(100), tags text[], bin bytea, count integer)",
  "CREATE TABLE comments (id serial PRIMARY KEY, text varchar(100), posted timestamp, interval interval, bytes bytea, post_id integer, author_id integer)",
  "CREATE TABLE permalinks (id serial PRIMARY KEY, url varchar(100), post_id integer)",
  "CREATE TABLE users (id serial PRIMARY KEY, name text)",
  "CREATE TABLE customs (foo text PRIMARY KEY)",
  "CREATE TABLE barebones (text text)",
  "CREATE TABLE transaction (id serial, text text)",
  "CREATE FUNCTION custom(integer) RETURNS integer AS 'SELECT $1 * 10;' LANGUAGE SQL"
]

{ :ok, _pid } = TestRepo.start_link

Enum.each(setup_database, fn(sql) ->
  result = Mysql.query(TestRepo, sql, [])
  if match?({ :error, _ }, result) do
    IO.puts("Test database setup SQL error'd: `#{sql}`")
    IO.inspect(result)
    System.halt(1)
  end
end)
