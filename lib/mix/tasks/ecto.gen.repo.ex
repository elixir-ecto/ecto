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
    no_umbrella!("ecto.gen.repo")
    {repo, _} = parse_repo(args)

    config      = Mix.Project.config
    underscored = Mix.Utils.underscore(inspect(repo))
    base        = Path.basename(underscored)
    file        = Path.join("lib", underscored) <> ".ex"
    app         = config[:app] || :YOUR_APP_NAME

    create_directory Path.dirname(file)
    create_file file, repo_template(mod: repo, app: app, base: base)
    open?(file)

    unless config[:build_per_environment] do
      Mix.shell.info "We have generated a repo that uses a different database per environment. " <>
                     "So don't forget to set [build_per_environment: true] in your mix.exs file.\n"
    end

    Mix.shell.info """
    Don't forget to add your new repo to your supervision tree as:

        worker(#{inspect repo}, [])
    """
  end

  embed_template :repo, """
  defmodule <%= inspect @mod %> do
    use Ecto.Repo, adapter: Ecto.Adapters.Postgres, env: Mix.env

    @doc "Adapter configuration"
    def conf(env), do: parse_url url(env)

    @doc "The URL to reach the database."
    defp url(:dev) do
      "ecto://user:pass@localhost/<%= @app %>_<%= @base %>_dev"
    end

    defp url(:test) do
      "ecto://user:pass@localhost/<%= @app %>_<%= @base %>_test?size=1&max_overflow=0"
    end

    defp url(:prod) do
      "ecto://user:pass@localhost/<%= @app %>_<%= @base %>_prod"
    end

    @doc "The priv directory to load migrations and metadata."
    def priv do
      app_dir(<%= inspect @app %>, "priv/<%= @base %>")
    end
  end
  """
end
