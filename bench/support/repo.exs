pg_bench_url = System.get_env("PG_URL") || "postgres:postgres@localhost"
mysql_bench_url = System.get_env("MYSQL_URL") || "root@localhost"

Application.put_env(
  :ecto,
  Ecto.Bench.PgRepo,
  url: "ecto://" <> pg_bench_url <> "/ecto_test",
  adapter: Ecto.Adapters.Postgres
)

Application.put_env(
  :ecto,
  Ecto.Bench.MySQLRepo,
  url: "ecto://" <> mysql_bench_url <> "/ecto_test",
  adapter: Ecto.Adapters.MySQL
)

defmodule Ecto.Bench.PgRepo do
  use Ecto.Repo, otp_app: :ecto, adapter: Ecto.Adapters.Postgres, log: false
end

defmodule Ecto.Bench.MySQLRepo do
  use Ecto.Repo, otp_app: :ecto, adapter: Ecto.Adapters.MySQL, log: false
end
