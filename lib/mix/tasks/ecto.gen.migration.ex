defmodule Mix.Tasks.Ecto.Gen.Migration do
  use Mix.Task
  import Mix.Tasks.Ecto
  import Mix.Generator
  import Mix.Utils, only: [camelize: 1]

  @shortdoc "Generates a new migration for the repo"

  @moduledoc """
  Generates a migration for the given repository.

  ## Command line options

  * `--no-start` - do not start applications

  ## Examples

      mix ecto.gen.migration MyApp.Repo add_posts_table
  """
  def run(args) do
    no_umbrella!("ecto.gen.migration")
    Mix.Task.run "app.start", args
    {_, args, _} = OptionParser.parse(args)

    case parse_repo(args) do
      {repo, [name]} ->
        ensure_repo(repo)
        path = Path.relative_to(migrations_path(repo), Mix.Project.app_path)
        file = Path.join(path, "#{timestamp}_#{name}.exs")
        create_directory path
        create_file file, migration_template(mod: Module.concat([repo, Migrations, camelize(name)]))

        if open?(file) && Mix.shell.yes?("Do you want to run this migration?") do
          Mix.Task.run "ecto.migrate", [repo]
        end
      {_repo, _} ->
        raise Mix.Error, message:
              "expected ecto.gen.migration to receive the migration file name, got: #{inspect Enum.join(args, " ")}"
    end
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
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
