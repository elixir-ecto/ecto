alias Ecto.Bench.User

struct = struct(User, User.data)

inputs = %{
  "Small (1 Thousand)" => 1_000,
  "Medium (5 Thousand)" => 5_000,
  "Big (10 Thousand)" => 10_000
}

jobs = %{
  "Pg Repo.all/2" => fn limit -> Ecto.Bench.PgRepo.all(User, limit: ^limit) end,
  "MySQL Repo.all/2" => fn limit -> Ecto.Bench.MySQLRepo.all(User, limit: ^limit) end
}

path = System.get_env("BENCHMARKS_OUTPUT_PATH") || raise "I DON'T KNOW WHERE TO WRITE!!!"
file = Path.join(path, "all.json")

Benchee.run(
  jobs,
  inputs: inputs,
  formatters: [Benchee.Formatters.JSON],
  formatter_options: [json: [file: file]]
)
