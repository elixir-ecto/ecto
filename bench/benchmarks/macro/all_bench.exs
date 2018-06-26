# -----------------------------------Goal--------------------------------------
# Compare the performance of querying all objects of the different supported
# databases

# -------------------------------Description-----------------------------------
# This benchmark tracks performance of querying a set of objects registered in
# the database with Repo.all/2 function. The query pass through
# the steps of translating the SQL statements, sending them to the database and
# load the results into Ecto structures. Both, Ecto Adapters and Database itself
# play a role and can affect the results of this benchmark.

# ----------------------------Factors(don't change)---------------------------
# Different adapters supported by Ecto with the proper database up and running

# ----------------------------Parameters(change)-------------------------------
# There is only a unique parameter in this benchmark, the User objects to be
# fetched.

alias Ecto.Bench.User

limit = 5_000

users =
  1..limit
  |> Enum.map(fn _ -> User.sample_data() end)

# We need to insert data to fetch
Ecto.Bench.PgRepo.insert_all(User, users)
Ecto.Bench.MySQLRepo.insert_all(User, users)

jobs = %{
  "Pg Repo.all/2" => fn -> Ecto.Bench.PgRepo.all(User, limit: limit) end,
  "MySQL Repo.all/2" => fn -> Ecto.Bench.MySQLRepo.all(User, limit: limit) end
}

path = System.get_env("BENCHMARKS_OUTPUT_PATH") || raise "I DON'T KNOW WHERE TO WRITE!!!"
file = Path.join(path, "all.json")

Benchee.run(
  jobs,
  formatters: [Benchee.Formatters.JSON],
  formatter_options: [json: [file: file]],
  time: 10
)

# Clean inserted data
Ecto.Bench.PgRepo.delete_all(User)
Ecto.Bench.MySQLRepo.delete_all(User)
