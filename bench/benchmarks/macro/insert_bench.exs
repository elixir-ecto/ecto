alias Ecto.Bench.User

inputs = %{
  "Struct" => struct(User, User.data()),
  "Changeset" => User.changeset(User.data()
}

jobs = %{
  "Pg Insert" => fn data -> Ecto.Bench.PgRepo.insert!(data) end,
  "MySQL Insert" => fn data -> Ecto.Bench.MySQLRepo.insert!(data) end
}

path = System.get_env("BENCHMARKS_OUTPUT_PATH") || raise "I DON'T KNOW WHERE TO WRITE!!!"
file = Path.join(path, "insert.json")

Benchee.run(
  jobs,
  inputs: inputs,
  formatters: [Benchee.Formatters.JSON],
  formatter_options: [json: [file: file]]
)
