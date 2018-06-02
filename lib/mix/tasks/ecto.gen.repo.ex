defmodule Mix.Tasks.Ecto.Gen.Repo do
  use Mix.Task

  import Mix.Ecto
  import Mix.Generator

  @shortdoc "Generates a new repository"

  @moduledoc """
  Generates a new repository.

  The repository will be placed in the `lib` directory.

  ## Examples

      mix ecto.gen.repo -r Custom.Repo

  This generator will automatically open the config/config.exs
  after generation if you have `ECTO_EDITOR` set in your environment
  variable.

  ## Command line options

    * `-r`, `--repo` - the repo to generate

  """

  @doc false
  def run(args) do
    no_umbrella!("ecto.gen.repo")

    repo =
      case parse_repo(args) do
        [] -> Mix.raise "ecto.gen.repo expects the repository to be given as -r MyApp.Repo"
        [repo] -> repo
        [_ | _] -> Mix.raise "ecto.gen.repo expects a single repository to be given"
      end

    config      = Mix.Project.config
    underscored = Macro.underscore(inspect(repo))

    base = Path.basename(underscored)
    file = Path.join("lib", underscored) <> ".ex"
    app  = config[:app] || :YOUR_APP_NAME
    opts = [mod: repo, app: app, base: base]

    create_directory Path.dirname(file)
    create_file file, repo_template(opts)

    case File.read "config/config.exs" do
      {:ok, contents} ->
        Mix.shell.info [:green, "* updating ", :reset, "config/config.exs"]
        File.write! "config/config.exs",
                    String.replace(contents, "use Mix.Config\n", config_template(opts))
      {:error, _} ->
        create_file "config/config.exs", config_template(opts)
    end

    open?("config/config.exs")

    Mix.shell.info """
    Don't forget to add your new repo to your supervision tree
    (typically in lib/#{app}/application.ex):

        # For Elixir v1.5 and later
        {#{inspect repo}, []}

        # For Elixir v1.4 and earlier
        supervisor(#{inspect repo}, [])

    And to add it to the list of ecto repositories in your
    configuration files (so Ecto tasks work as expected):

        config #{inspect app},
          ecto_repos: [#{inspect repo}]

    """
  end

  embed_template :repo, """
  defmodule <%= inspect @mod %> do
    use Ecto.Repo,
      otp_app: <%= inspect @app %>,
      adapter: Ecto.Adapters.Postgres
  end
  """

  embed_template :config, """
  use Mix.Config

  config <%= inspect @app %>, <%= inspect @mod %>,
    database: "<%= @app %>_<%= @base %>",
    username: "user",
    password: "pass",
    hostname: "localhost"
  """
end
