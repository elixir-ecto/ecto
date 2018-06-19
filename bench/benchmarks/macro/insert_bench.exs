alias Ecto.Bench.User

data = User.data()

struct = struct(User, User.data())

changeset = User.changeset(data)

inputs = %{"pg" => Ecto.Bench.PgRepo, "mysql" => Ecto.Bench.MySQLRepo}

jobs = %{
  "insert_plain" => fn repo -> repo.insert!(struct) end,
  "insert_changeset" => fn repo -> repo.insert!(changeset) end
}

path = System.get_env("BENCHMARKS_OUTPUT_PATH") || raise "I DON'T KNOW WHERE TO WRITE!!!"
file = Path.join(path, "insert.json")

Benchee.run(
  jobs,
  inputs: inputs,
  formatters: [Benchee.Formatters.JSON],
  formatter_options: [json: [file: file]]
)
