ExUnit.start

alias Ecto.PgTest.TestRepo
alias Ecto.Adapters.Postgres

defmodule Ecto.PgTest.TestRepo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres

  def url do
    "ecto://ecto_test:ecto_test@localhost/ecto_test?size=1&max_overflow=0"
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
  "dropdb ecto_test",
  "createdb ecto_test -O ecto_test"
]

Enum.each(setup_cmds, fn(cmd) ->
  output = System.cmd(cmd)
  if output != "" do
    IO.puts "Test setup command error'd: `#{cmd}`"
    IO.puts output
    System.halt
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
    System.halt
  end
end)
