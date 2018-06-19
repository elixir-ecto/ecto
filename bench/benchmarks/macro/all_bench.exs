alias Ecto.Bench.User

limit = 5_000

users =
1..limit
|> Enum.map(fn _ -> User.sample_data() end)

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
