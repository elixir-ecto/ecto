defmodule Ecto.Bench.User do
  use Ecto.Schema

  schema "users" do
    field(:name, :string)
    field(:email, :string)
    timestamps()
  end

  def changeset(data) do
    Ecto.Changeset.cast(%__MODULE__{}, data, [:name, :email])
  end
end

alias Ecto.Bench.User

data = %{
  name: "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
  email: "foobar@email.com"
}

struct = struct(User, data)

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
