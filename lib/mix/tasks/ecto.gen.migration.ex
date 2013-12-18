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
      { repo, [repo_name] } ->
        ensure_repo(repo)
        params = get_params(repo, repo_name)
        create_file_with_dir params[:file_name], &migration_template/1, params

        if open?(params[:file_name]) && Mix.shell.yes?("Do you want to run this migration?") do
          Mix.Task.run "ecto.migrate", [repo]
        end
      { _repo, _ } ->
        raise Mix.Error, message:
              "expected ecto.gen.migration to receive the migration file name, got: #{inspect Enum.join(args, " ")}"
    end
  end

  def get_params(repo, repo_name) do
    [ file_name: Path.join(migrations_path(repo), "#{timestamp}_#{repo_name}.exs"),
      module_name: Module.concat([repo, Migrations, camelize(repo_name)])
    ]
  end

  embed_template :migration, """
  defmodule <%= inspect @module_name %> do
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
