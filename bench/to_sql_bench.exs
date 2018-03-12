# -----------------------------------Goal--------------------------------------
# Compare the implementation of parsing Ecto.Query objects into SQL queries by
# the different database adapters

# -------------------------------Description-----------------------------------
# Repo.to_sql/2 is an important step of a database query.
# This benchmark tracks performance of parsing Ecto.Query structures into
# "raw" SQL query strings.
# Different Ecto.Query objects has multiple combinations and some different attributes
# depending on the query type. In this tests we benchmark against different
# query types and complexity.

# ----------------------------Factores(don't change)---------------------------
# Different adapters supported by Ecto, each one has its own implementation that
# is tested against different query inputs

# ----------------------------Parameters(change)-------------------------------
# Different query objects (select, delete, update) to be translated into pure SQL
# strings.

import Ecto.Query

alias Ecto.Bench.User

inputs = %{
  "Ordinary Select All" => {:all, from(User)} ,
  "Ordinary Delete All" => {:delete_all, from(User)},
  "Ordinary Update All" => {:update_all, from(User, update: [set: [name: ^"Thor"]])},
  "Simple Where" => {:all, from(User, where: [name: ^"Thanos", email: ^"blah"])},
  "Fetch First Registry" => {:all, first(User)},
  "Fetch Last Registry" => {:all, last(User)},
  "Simple Order By" => {:all, order_by(User, desc: :name)}
}

jobs = %{
  "PG Query Builder" => fn {type, query} -> Ecto.Bench.PgRepo.to_sql(type, query) end,
  "MySQL Query Builder" => fn {type, query} -> Ecto.Bench.MySQLRepo.to_sql(type, query) end
}

path = System.get_env("BENCHMARKS_OUTPUT_PATH") || raise "I DON'T KNOW WHERE TO WRITE!!!"
file = Path.join(path, "to_sql.json")

Benchee.run(
  jobs,
  inputs: inputs,
  formatters: [Benchee.Formatters.JSON],
  formatter_options: [json: [file: file]],
)
