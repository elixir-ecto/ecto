Application.put_env(
  :ecto,
  :pg_bench_url,
  "ecto://" <> (System.get_env("PG_URL") || "postgres:postgres@localhost")
)

Application.put_env(
  :ecto,
  :mysql_bench_url,
  "ecto://" <> (System.get_env("MYSQL_URL") || "root@localhost")
)

Code.require_file("support/setup.exs", __DIR__)

Code.load_file("load_bench.exs", __DIR__)
Code.load_file("to_sql_bench.exs", __DIR__)

# Needs postgresql and mysql up and running
# Code.load_file("insert_bench.exs", __DIR__)
