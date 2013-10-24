defmodule Mix.Tasks.Ecto.Gen.Repo do
  use Mix.Task

  import Mix.Tasks.Ecto
  import Mix.Generator

  @shortdoc "Generates a new repository"

  @moduledoc """
  Generates a new repository.

  The repository will be placed in the `lib` directory.

  ## Examples

      mix ecto.gen.repo Repo

  """
  def run(args) do
    { repo, _ } = parse_repo(args)

    underscored = Mix.Utils.underscore(inspect(repo))
    base = Path.basename(underscored)
    file = Path.join("lib", underscored) <> ".ex"
    app  = Mix.project[:app] || :YOUR_APP_NAME

    create_directory Path.dirname(file)
    create_file file, repo_template(mod: repo, app: app, base: base)
    open?(file)
  end

  embed_template :repo, """
  defmodule <%= inspect @mod %> do
    use Ecto.Repo, adapter: Ecto.Adapters.Postgres

    def priv do
      app_dir(<%= inspect @app %>, "priv/<%= @base %>")
    end

    def url do
      "ecto://postgres:postgres@localhost/<%= @app %>_<%= @base %>"
    end
  end
  """
end
