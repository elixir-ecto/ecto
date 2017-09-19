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
    apps =
      if apps_paths = Mix.Project.apps_paths do
        Map.keys(apps_paths)
      else
        [Mix.Project.config[:app]]
      end

    apps
    |> Enum.flat_map(&Application.get_env(&1, :ecto_repos, []))
    |> Enum.uniq()
    |> case do
      [] ->
        Mix.shell.error """
        warning: could not find Ecto repos in any of the apps: #{inspect apps}.

        You can avoid this warning by passing the -r flag or by setting the
        repositories managed by those applications in your config/config.exs:

            config #{inspect hd(apps)}, ecto_repos: [...]
        """
        []
      repos ->
        repos
    end
  end

  defp parse_repo([], acc) do
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
          Mix.raise "Module #{inspect repo} is not an Ecto.Repo. " <>
                    "Please configure your app accordingly or pass a repo with the -r option."
        end
      {:error, error} ->
        Mix.raise "Could not load #{inspect repo}, error: #{inspect error}. " <>
                  "Please configure your app accordingly or pass a repo with the -r option."
    end
  end

  @doc """
  Ensures the given repository is started and running.
  """
  @spec ensure_started(Ecto.Repo.t, Keyword.t) :: {:ok, pid, [atom]} | no_return
  def ensure_started(repo, opts) do
    {:ok, started} = Application.ensure_all_started(:ecto)

    # If we starting Ecto just now, assume
    # logger has not been properly booted yet.
    if :ecto in started && Process.whereis(Logger) do
      backends = Application.get_env(:logger, :backends, [])
      try do
        Logger.App.stop
        Application.put_env(:logger, :backends, [:console])
        :ok = Logger.App.start
      after
        Application.put_env(:logger, :backends, backends)
      end
    end

    {:ok, apps} = repo.__adapter__.ensure_all_started(repo, :temporary)

    pool_size = Keyword.get(opts, :pool_size, 1)
    case repo.start_link(pool_size: pool_size) do
      {:ok, pid} ->
        {:ok, pid, apps}
      {:error, {:already_started, _pid}} ->
        {:ok, nil, apps}
      {:error, error} ->
        Mix.raise "Could not start repo #{inspect repo}, error: #{inspect error}"
    end
  end

  @doc """
  Ensures the given repository's migrations path exists on the file system.
  """
  @spec ensure_migrations_path(Ecto.Repo.t) :: Ecto.Repo.t | no_return
  def ensure_migrations_path(repo) do
    with false <- Mix.Project.umbrella?,
         path = Path.relative_to(migrations_path(repo), Mix.Project.app_path),
         false <- File.dir?(path),
         do: raise_missing_migrations(path, repo)
    repo
  end

  defp raise_missing_migrations(path, repo) do
    Mix.raise """
    Could not find migrations directory #{inspect path}
    for repo #{inspect repo}.

    This may be because you are in a new project and the
    migration directory has not been created yet. Creating an
    empty directory at the path above will fix this error.

    If you expected existing migrations to be found, please
    make sure your repository has been properly configured
    and the configured path exists.
    """
  end

  @doc """
  Restarts the app if there was any migration command.
  """
  @spec restart_apps_if_migrated([atom], list()) :: :ok
  def restart_apps_if_migrated(_apps, []), do: :ok
  def restart_apps_if_migrated(apps, [_|_]) do
    # Silence the logger to avoid application down messages.
    Logger.remove_backend(:console)
    for app <- Enum.reverse(apps) do
      Application.stop(app)
    end
    for app <- apps do
      Application.ensure_all_started(app)
    end
    :ok
  after
    Logger.add_backend(:console, flush: true)
  end

  @doc """
  Gets the migrations path from a repository.
  """
  @spec migrations_path(Ecto.Repo.t) :: String.t
  def migrations_path(repo) do
    Path.join(source_repo_priv(repo), "migrations")
  end

  @doc """
  Returns the private repository path relative to the source.
  """
  def source_repo_priv(repo) do
    priv = repo.config()[:priv] || "priv/#{repo |> Module.split |> List.last |> Macro.underscore}"
    app = Keyword.fetch!(repo.config(), :otp_app)
    Path.join(Mix.Project.deps_paths[app] || File.cwd!, priv)
  end

  @doc """
  Asks if the user wants to open a file based on ECTO_EDITOR.
  """
  @spec open?(binary) :: boolean
  def open?(file) do
    editor = System.get_env("ECTO_EDITOR") || ""
    if editor != "" do
      :os.cmd(to_charlist(editor <> " " <> inspect(file)))
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
