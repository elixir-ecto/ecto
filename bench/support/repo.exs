Application.put_env(
  :ecto,
  Ecto.Bench.PgRepo,
  url: Application.get_env(:ecto, :pg_bench_url) <> "/ecto_test"
)

Application.put_env(
  :ecto,
  Ecto.Bench.MySQLRepo,
  url: Application.get_env(:ecto, :mysql_bench_url) <> "/ecto_test"
)

defmodule Ecto.Bench.PgRepo do
  use Ecto.Repo, otp_app: :ecto, adapter: Ecto.Adapters.Postgres, loggers: []
end

defmodule Ecto.Bench.MySQLRepo do
  use Ecto.Repo, otp_app: :ecto, adapter: Ecto.Adapters.MySQL, loggers: []
end
