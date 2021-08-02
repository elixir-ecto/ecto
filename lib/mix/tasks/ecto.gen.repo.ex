defmodule Mix.Tasks.Ecto.Gen.Repo do
  use Mix.Task

  import Mix.Ecto
  import Mix.Generator

  @shortdoc "Generates a new repository"

  @switches [
    repo: [:string, :keep],
  ]

  @aliases [
    r: :repo,
  ]

  @moduledoc """
  Generates a new repository.

  The repository will be placed in the `lib` directory.

  ## Examples

      $ mix ecto.gen.repo -r Custom.Repo

  This generator will automatically open the config/config.exs
  after generation if you have `ECTO_EDITOR` set in your environment
  variable.

  ## Command line options

    * `-r`, `--repo` - the repo to generate

  """

  @impl true
  def run(args) do
    no_umbrella!("ecto.gen.repo")
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    repo =
      case Keyword.get_values(opts, :repo) do
        [] -> Mix.raise "ecto.gen.repo expects the repository to be given as -r MyApp.Repo"
        [repo] -> Module.concat([repo])
        [_ | _] -> Mix.raise "ecto.gen.repo expects a single repository to be given"
      end

    config      = Mix.Project.config()
    underscored = Macro.underscore(inspect(repo))

    base = Path.basename(underscored)
    file = Path.join("lib", underscored) <> ".ex"
    app  = config[:app] || :YOUR_APP_NAME
    opts = [mod: repo, app: app, base: base]

    create_directory Path.dirname(file)
    create_file file, repo_template(opts)
    config_path = config[:config_path] || "config/config.exs"

    case File.read(config_path) do
      {:ok, contents} ->
        check = String.contains?(contents, "import Config")
        config_first_line = get_first_config_line(check) <> "\n"
        new_contents = config_first_line <> "\n" <> config_template(opts)
        Mix.shell().info [:green, "* updating ", :reset, config_path]
        File.write! config_path, String.replace(contents, config_first_line, new_contents)
      {:error, _} ->
        config_first_line = Config |> Code.ensure_loaded?() |> get_first_config_line()
        create_file config_path, config_first_line <> "\n\n" <> config_template(opts)
    end

    open?(config_path, 3)

    Mix.shell().info """
    Don't forget to add your new repo to your supervision tree
    (typically in lib/#{app}/application.ex):

        {#{inspect repo}, []}

    And to add it to the list of Ecto repositories in your
    configuration files (so Ecto tasks work as expected):

        config #{inspect app},
          ecto_repos: [#{inspect repo}]

    """
  end

  defp get_first_config_line(true), do: "import Config"
  defp get_first_config_line(false), do: "use Mix.Config"

  embed_template :repo, """
  defmodule <%= inspect @mod %> do
    use Ecto.Repo,
      otp_app: <%= inspect @app %>,
      adapter: Ecto.Adapters.Postgres
  end
  """

  embed_template :config, """
  config <%= inspect @app %>, <%= inspect @mod %>,
    database: "<%= @app %>_<%= @base %>",
    username: "user",
    password: "pass",
    hostname: "localhost"
  """
end
