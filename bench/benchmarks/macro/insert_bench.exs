alias Ecto.Bench.User

inputs = %{
  "Struct" => struct(User, User.sample_data()),
  "Changeset" => User.changeset(User.sample_data())
}

jobs = %{
  "Pg Insert" => fn entry -> Ecto.Bench.PgRepo.insert!(entry) end,
  "MySQL Insert" => fn entry -> Ecto.Bench.MySQLRepo.insert!(entry) end
}

path = System.get_env("BENCHMARKS_OUTPUT_PATH") || raise "I DON'T KNOW WHERE TO WRITE!!!"
file = Path.join(path, "insert.json")

Benchee.run(
  jobs,
  inputs: inputs,
  formatters: [Benchee.Formatters.JSON],
  formatter_options: [json: [file: file]]
)
