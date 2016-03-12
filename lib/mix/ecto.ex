defmodule Mix.Ecto do
  # Conveniences for writing Mix.Tasks in Ecto.
  @moduledoc false

  @doc """
  Parses the repository option from the given list.

  If no repo option is given, we get one from the environment.
  """
  @spec parse_repo([term]) :: [Ecto.Repo.t]
  def parse_repo(args) do
    parse_repo(args, [])
  end

  defp parse_repo([key, value|t], acc) when key in ~w(--repo -r) do
    parse_repo t, [Module.concat([value])|acc]
  end

  defp parse_repo([_|t], acc) do
    parse_repo t, acc
  end

  defp parse_repo([], []) do
    if app = Keyword.get(Mix.Project.config, :app) do
      case Application.get_env(app, :app_repo) do
        nil ->
          case Application.get_env(app, :app_namespace, app) do
            ^app -> app |> to_string |> Mix.Utils.camelize
            mod  -> mod |> inspect
          end |> Module.concat(Repo)
        repo ->
          repo
      end |> List.wrap
    else
      Mix.raise "No repository available (project #{inspect Mix.Project.get} has no :app configured). " <>
                "Please pass a repo with the -r option."
    end
  end

  defp parse_repo([], acc) do
    Enum.reverse(acc)
  end


  @doc """
  Parses the file option from the given list.

  If no file option is given we assume `{priv_dir(repo)}/structure.sql`
  """
  def parse_file(args, repo) do
    parse_file(args, [], repo)
  end

  defp parse_file([key, path | t], _acc, _repo) when key in ~w(--file -f) do
    path
  end

  defp parse_file([_|t], acc, repo) do
    parse_file t, acc, repo
  end

  defp parse_file([], [], repo) do
    Path.relative_to(repo_priv(repo), Mix.Project.app_path)
    |> Path.join("structure.sql")
  end

  defp parse_file([], acc, _repo) do
    Enum.reverse(acc)
  end

  @doc """
  Ensures the given module is a repository.
  """
  @spec ensure_repo(module, list) :: Ecto.Repo.t | no_return
  def ensure_repo(repo, args) do
    Mix.Task.run "loadpaths", args

    unless "--no-compile" in args do
      Mix.Project.compile(args)
    end

    case Code.ensure_compiled(repo) do
      {:module, _} ->
        if function_exported?(repo, :__adapter__, 0) do
          repo
        else
          Mix.raise "Module #{inspect repo} is not a Ecto.Repo. " <>
                    "Please pass a repo with the -r option."
        end
      {:error, error} ->
        Mix.raise "Could not load #{inspect repo}, error: #{inspect error}. " <>
                  "Please pass a repo with the -r option."
    end
  end

  @doc """
  Ensures the given repository is started and running.
  """
  @spec ensure_started(Ecto.Repo.t, Keyword.t) :: Ecto.Repo.t | no_return
  def ensure_started(repo, opts) do
    {:ok, _} = Application.ensure_all_started(:ecto)
    {:ok, _} = Application.ensure_all_started(repo.__adapter__.application)

    pool_size = Keyword.get(opts, :pool_size, 1)
    case repo.start_link(pool_size: pool_size) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:ok, nil}
      {:error, error} ->
        Mix.raise "Could not start repo #{inspect repo}, error: #{inspect error}"
    end
  end

  @doc """
  Ensures the given repository's migrations path exists on the filesystem.
  """
  @spec ensure_migrations_path(Ecto.Repo.t) :: Ecto.Repo.t | no_return
  def ensure_migrations_path(repo) do
    with false <- Mix.Project.umbrella?,
         path = Path.relative_to(migrations_path(repo), Mix.Project.app_path),
         false <- File.dir?(path),
         do: Mix.raise "Could not find migrations directory #{inspect path} for repo #{inspect repo}"
    repo
  end

  @doc """
  Restarts the app if there was any migration command.
  """
  def restart_app_if_migrated(_repo, []), do: :ok
  def restart_app_if_migrated(repo, [_|_]) do
    # Silence the logger to avoid application down messages.
    Logger.remove_backend(:console)
    app = repo.__adapter__.application
    Application.stop(app)
    Application.ensure_all_started(app)
  after
    Logger.add_backend(:console, flush: true)
  end

  @doc """
  Gets the migrations path from a repository.
  """
  @spec migrations_path(Ecto.Repo.t) :: String.t
  def migrations_path(repo) do
    Path.join(repo_priv(repo), "migrations")
  end

  @doc """
  Dumps the database structure

  Will dump the structure of the database via the given repo's adapter
  """
  @spec structure_dump(Ecto.Repo.t) :: no_return
  def structure_dump(repo) do
    {dump, 0} = repo.__adapter__.structure_dump(repo.config)
    dump
  end

  @doc """
  Loads the database structure

  Will load the structure into a database via the given repo's adapter
  """
  @spec structure_load(Ecto.Repo.t, String) :: no_return
  def structure_load(repo, path) do
    {_, 0} = repo.__adapter__.structure_load(repo.config, path)
  end

  @doc """
  Returns the private repository path.
  """
  def repo_priv(repo) do
    config = repo.config()

    Application.app_dir(Keyword.fetch!(config, :otp_app),
      config[:priv] || "priv/#{repo |> Module.split |> List.last |> Macro.underscore}")
  end

  @doc """
  Asks if the user wants to open a file based on ECTO_EDITOR.
  """
  @spec open?(binary) :: boolean
  def open?(file) do
    editor = System.get_env("ECTO_EDITOR") || ""
    if editor != "" do
      :os.cmd(to_char_list(editor <> " " <> inspect(file)))
      true
    else
      false
    end
  end

  @doc """
  Gets a path relative to the application path.
  Raises on umbrella application.
  """
  def no_umbrella!(task) do
    if Mix.Project.umbrella? do
      Mix.raise "Cannot run task #{inspect task} from umbrella application"
    end
  end

  @doc """
  Returns `true` if module implements behaviour.
  """
  def ensure_implements(module, behaviour, message) do
    all = Keyword.take(module.__info__(:attributes), [:behaviour])
    unless [behaviour] in Keyword.values(all) do
      Mix.raise "Expected #{inspect module} to implement #{inspect behaviour} " <>
                "in order to #{message}"
    end
  end
end
