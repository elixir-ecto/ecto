ExUnit.start

alias Ecto.PgTest.TestRepo
alias Ecto.Adapters.Postgres

defmodule Ecto.PgTest.TestRepo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres

  def url do
    "ecto://postgres:postgres@localhost/ecto_test?size=1&max_overflow=0"
  end
end

defmodule Ecto.PgTest.Post do
  use Ecto.Entity

  schema "posts" do
    field :title, :string
    field :text, :string
  end
end

defmodule Ecto.PgTest.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__)
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
  "psql -U postgres -c \"DROP DATABASE IF EXISTS ecto_test;\"",
  "psql -U postgres -c \"CREATE DATABASE ecto_test;\""
]

Enum.each(setup_cmds, fn(cmd) ->
  key = :ecto_setup_cmd_output
  Process.put(key, "")
  status = Mix.Shell.cmd(cmd, fn(data) ->
    current = Process.get(key)
    Process.put(key, current <> data)
  end)

  if status != 0 do
    IO.puts("Test setup command error'd: `#{cmd}`")
    IO.puts(Process.get(key))
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
    IO.puts "Test database setup SQL error'd: `#{sql}`"
    IO.inspect result
    System.halt(1)
  end
end)
