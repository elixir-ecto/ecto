ExUnit.start

alias Ecto.Adapters.Postgres

defmodule TestRepo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres

  def url do
    "ecto://postgres:postgres@localhost/ecto_test?size=1&max_overflow=0"
  end
end

defmodule Post do
  use Ecto.Entity

  dataset "posts" do
    field :title, :string
    field :text, :string
  end
end

defmodule Ecto.PgTest.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__)
      require TestRepo
    end
  end

  setup do
    :ok = Postgres.transaction_begin(TestRepo)
  end

  teardown do
    :ok = Postgres.transaction_rollback(TestRepo)
  end
end

setup_cmds = [
  %b(psql -U postgres -c "DROP DATABASE IF EXISTS ecto_test;"),
  %b(psql -U postgres -c "CREATE DATABASE ecto_test ENCODING='UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8';")
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
  "CREATE TABLE posts (id serial PRIMARY KEY, title varchar(100), text varchar(100))"
]

{ :ok, _pid } = Postgres.start(TestRepo)

Enum.each(setup_database, fn(sql) ->
  result = Postgres.query(TestRepo, sql)
  if match?({ :error, _ }, result) do
    IO.puts("Test database setup SQL error'd: `#{sql}`")
    IO.inspect(result)
    System.halt(1)
  end
end)
