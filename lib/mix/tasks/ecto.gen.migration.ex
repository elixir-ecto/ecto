defmodule Mix.Tasks.Ecto.Gen.Migration do
  use Mix.Task
  import Mix.Tasks.Ecto
  import Mix.Generator
  import Mix.Utils, only: [camelize: 1]

  @shortdoc "Generates a new migration for the repo"

  @moduledoc """
  Generates a migration for the given repository.

  ## Examples

      mix ecto.gen.migration MyApp.Repo add_posts_table

  """
  def run(args) do
    case parse_repo(args) do
      { repo, [file] } ->
        path = migrations_path(repo)
        create_directory path
        create_file Path.join(path, "#{timestamp}_#{file}.exs"),
                    migration_template(mod: Module.concat(repo, camelize(file)))
      { _repo, _ } ->
        raise Mix.Error, message:
              "expected ecto.gen.migration to receive the migration file name, got: #{inspect Enum.join(args, " ")}"
    end
  end

  defp timestamp do
    { { y, m, d }, { hh, mm, ss } } = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: << ?0, ?0 + i >>
  defp pad(i), do: to_string(i)

  embed_template :migration, """
  defmodule <%= inspect @mod %> do
    use Ecto.Migration

    def up do
      ""
    end

    def down do
      ""
    end
  end
  """
end
