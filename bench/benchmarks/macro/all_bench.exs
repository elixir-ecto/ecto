alias Ecto.Bench.User

inputs = %{"pg" => Ecto.Bench.PgRepo, "mysql" => Ecto.Bench.MySQLRepo}

jobs = %{
  "all_with_small_dataset" => fn repo -> repo.all(User, limit: 10) end,
  "all_with_medium_dataset" => fn repo -> repo.all(User, limit: 100) end,
  "all_with_big_dataset" => fn repo -> repo.all(User, limit: 1000) end
}

struct = struct(User, User.data)

insert_all = fn data, repo_list ->
  repo_list
  |> Enum.each(fn { _, repo} -> repo.insert_all(User, data) end)
end

1..1000
|> Enum.map(fn _ -> User.data end)
|> insert_all.(inputs)


path = System.get_env("BENCHMARKS_OUTPUT_PATH") || raise "I DON'T KNOW WHERE TO WRITE!!!"
file = Path.join(path, "all.json")

Benchee.run(
  jobs,
  inputs: inputs,
  formatters: [Benchee.Formatters.JSON],
  formatter_options: [json: [file: file]]
)
