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

# Initialize 
Code.require_file("support/setup.exs", __DIR__)

# Micro benchmarks 
Code.load_file("benchmarks/micro/load_bench.exs", __DIR__)
Code.load_file("benchmarks/micro/to_sql_bench.exs", __DIR__)

# Macro benchmarks needs postgresql and mysql up and running
# Code.load_file("benchmarks/macro/insert_bench.exs", __DIR__)
# Code.load_file("benchmarks/macro/all_bench.exs", __DIR__)
