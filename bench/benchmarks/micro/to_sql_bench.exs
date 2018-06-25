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

# ----------------------------Factors(don't change)---------------------------
# Different adapters supported by Ecto, each one has its own implementation that
# is tested against different query inputs

# ----------------------------Parameters(change)-------------------------------
# Different query objects (select, delete, update) to be translated into pure SQL
# strings.

import Ecto.Query

alias Ecto.Bench.{User, Game}

inputs = %{
  "Ordinary Select All" => {:all, from(User)},
  "Ordinary Delete All" => {:delete_all, from(User)},
  "Ordinary Update All" => {:update_all, from(User, update: [set: [name: "Thor"]])},
  "Ordinary Where" => {:all, from(User, where: [name: "Thanos", email: "blah@blah"])},
  "Fetch First Registry" => {:all, first(User)},
  "Fetch Last Registry" => {:all, last(User)},
  "Ordinary Order By" => {:all, order_by(User, desc: :name)},
  "Complex Query 2 Joins" =>
    {:all,
     from(User, where: [name: "Thanos"])
     |> join(:left, [u], ux in User, u.id == ux.id)
     |> join(:right, [j], uj in User, j.id == 1 and j.email == "email@email")
     |> select([u, ux], {u.name, ux.email})},
  "Complex Query 4 Joins" =>
    {:all,
     from(User)
     |> join(:left, [u], g in Game, g.name == u.name)
     |> join(:right, [g], u in User, g.id == 1 and u.email == "email@email")
     |> join(:inner, [u], g in fragment("SELECT * from games where game.id = ?", u.id))
     |> join(:left, [g], u in fragment("SELECT * from users = ?", g.id))
     |> select([u, g], {u.name, g.price})}
}

jobs = %{
  "Pg Query Builder" => fn {type, query} -> Ecto.Bench.PgRepo.to_sql(type, query) end,
  "MySQL Query Builder" => fn {type, query} -> Ecto.Bench.MySQLRepo.to_sql(type, query) end
}

path = System.get_env("BENCHMARKS_OUTPUT_PATH") || raise "I DON'T KNOW WHERE TO WRITE!!!"
file = Path.join(path, "to_sql.json")

Benchee.run(
  jobs,
  inputs: inputs,
  formatters: [Benchee.Formatters.JSON],
  formatter_options: [json: [file: file]]
)
