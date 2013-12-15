defmodule Mix.Tasks.Ecto.Gen.Model.Entity do
  use Mix.Task

  import Mix.Tasks.Ecto
  import Mix.Generator
  import Mix.Utils, only: [camelize: 1, underscore: 1]

  @shortdoc "Generates an ecto model and entity"

  @moduledoc """
  Generates a model and entity for a given repo.

  ## Examples

      mix ecto.gen.model.entity MyApp.Repo MyModel

  """

  def run(args) do
    case parse_repo(args) do
      { repo, [model_name|field_specs] } ->
        ensure_repo(repo)
        params = get_params(repo, model_name, field_specs)

        Path.dirname(params[:file_name]) |> create_directory
        create_file params[:file_name], model_template([
          mod: params[:module_name], table: params[:table_name], fields: params[:fields]
        ])
        open?(params[:file_name])

        Path.dirname(params[:test_file_name]) |> create_directory
        create_file params[:test_file_name], test_template([ mod: params[:module_name] ])
        open?(params[:test_file_name])
      { _repo, _ } ->
        raise Mix.Error, message:
              "expected ecto.gen.model.entity to receive the repo and model name, got: #{inspect Enum.join(args, " ")}"
    end
  end

  defp get_params(repo, model_name, field_specs) do
    # Get short repo name
    {:ok, repo_name} = to_string(repo) |> String.split(".") |> Enum.fetch(-1)

    underscored = model_name |> underscore
    [ module_name: model_name,
      table_name: (repo_name <> model_name) |> String.replace(".", "")|> underscore,
      file_name: Path.join("lib", underscored) <> ".ex",
      test_file_name: Path.join("test", underscored) <> "_test.exs",
      fields: Enum.map(field_specs, &field_from_spec(&1))
    ]
  end

  defp field_from_spec(spec) do
    [name, type] = String.split(spec, ":")
    "  field :#{name }, :#{type }"
  end

  embed_template :model, """
  defmodule <%= @mod %>.Entity do
    use Ecto.Entity

    <%= Enum.join(@fields, "\n    ") %>
  end

  defmodule <%= @mod %> do
    use Ecto.Model

    queryable "<%= @table %>", <%= @mod %>.Entity
  end
  """

  embed_template :test, """
  defmodule <%= @mod %>Test do
    use ExUnit.Case, async: true

    test "the truth" do
      assert true
    end
  end
  """
 end
