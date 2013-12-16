defmodule Mix.Tasks.Ecto.Gen.Model.Migration do
  use Mix.Task
  import Mix.Tasks.Ecto
  import Mix.Generator
  import Mix.Utils, only: [camelize: 1, underscore: 1]

  @shortdoc "Generates a new model-migration for the repo"

  @moduledoc """
  Generates a migration for the given repo and model.

  ## Examples

      mix ecto.gen.model.migration MyApp.Repo MyModel

  """
  def run(args) do
    case parse_repo(args) do
      { repo, [model_name|field_specs] } ->
        ensure_repo(repo)
        params = get_params(repo, model_name, field_specs)
        create_directory(params[:path])
        create_file params[:file_name], migration_template([
          mod: params[:module_name], table: params[:table_name], columns: params[:columns]
        ])

        if open?(params[:file]) && Mix.shell.yes?("Do you want to run this migration?") do
          Mix.Task.run "ecto.migrate", [repo]
        end
      { _repo, _ } ->
        raise Mix.Error, message:
              "expected ecto.gen.model.migration to receive the repo and model name, got: #{inspect Enum.join(args, " ")}"
    end
  end

  defp get_params(repo, model_name, field_specs) do
    # Get short repo name
    {:ok, repo_name} = to_string(repo) |> String.split(".") |> Enum.fetch(-1)

    model_name = String.replace model_name, ".", ""
    migration_name = "Create" <> model_name <> "Table" |> underscore
    path = migrations_path(repo)
    [ path: path,
      table_name: (repo_name <> model_name) |> underscore,
      migration_name: migration_name,
      module_name: Module.concat([repo, Migrations, camelize(migration_name)]),
      file_name: Path.join(path, "#{timestamp}_#{migration_name}.exs"),
      columns: columns_from_field_specs(repo, ["id:id"|field_specs])
    ]
  end

  defp columns_from_field_specs(repo, field_specs) do
    Enum.filter_map(
      field_specs,
      fn(spec) ->
        not (spec =~ %r/:virtual$/)
      end,
      fn(spec) ->
        [field_name, ecto_type] = String.split(spec, ":")
        "#{field_name} #{repo.adapter.type_map.for(ecto_type)}"
      end
    )
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
      \"\"\"
      CREATE TABLE IF NOT EXISTS <%= @table %> (
        <%= Enum.join(@columns, ",\n      ") %>
      );
      \"\"\"
    end

    def down do
      "DROP TABLE <%= @table %>;"
    end
  end
  """
end
