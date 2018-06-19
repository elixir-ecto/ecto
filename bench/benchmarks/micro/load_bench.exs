# -----------------------------------Goal--------------------------------------
# Compare the implementation of loading raw database data into Ecto structures by
# the different database adapters

# -------------------------------Description-----------------------------------
# Repo.load/2 is an important step of a database query.
# This benchmark tracks performance of loading "raw" data into ecto structures
# Raw data can be in different types (e.g. keyword lists, maps), in this tests
# we benchmark against map inputs

# ----------------------------Factors(don't change)---------------------------
# Different adapters supported by Ecto, each one has its own implementation that
# is tested against different inputs

# ----------------------------Parameters(change)-------------------------------
# Different sizes of raw data(small, medium, big) fetched from db that has to
# be loaded into Ecto structures.

alias Ecto.Bench.User

inputs = %{
  "Small (1 Thousand)" => 1..1_000 |> Enum.map(fn(_) -> %{name: "Alice", email: "email@email.com"} end),
  "Medium (100 Thousand)" => 1..100_000 |> Enum.map(fn(_) -> %{name: "Alice", email: "email@email.com"} end),
  "Big (1 Million)" => 1..1_000_000 |> Enum.map(fn(_) -> %{name: "Alice", email: "email@email.com"} end),
  "Large (5 Million)" => 1..5_000_000 |> Enum.map(fn(_) -> %{name: "Alice", email: "email@email.com"} end),
}

jobs = %{
  "Pg Loader" => fn data -> Enum.map(data, &Ecto.Bench.PgRepo.load(User, &1)) end,
  "MySQL Loader" => fn data -> Enum.map(data, &Ecto.Bench.MySQLRepo.load(User, &1)) end,
}

path = System.get_env("BENCHMARKS_OUTPUT_PATH") || raise "I DON'T KNOW WHERE TO WRITE!!!"
file = Path.join(path, "load.json")

Benchee.run(
  jobs,
  inputs: inputs,
  formatters: [Benchee.Formatters.JSON],
  formatter_options: [json: [file: file]]
)
