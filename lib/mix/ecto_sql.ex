defmodule Mix.EctoSQL do
  @moduledoc false

  @doc """
  Ensures the given repository is started and running.
  """
  @spec ensure_started(Ecto.Repo.t, Keyword.t) :: {:ok, pid | nil, [atom]}
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

    {:ok, apps} = repo.__adapter__.ensure_all_started(repo.config(), :temporary)
    pool_size = Keyword.get(opts, :pool_size, 2)

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
  @spec ensure_migrations_path(Ecto.Repo.t) :: Ecto.Repo.t
  def ensure_migrations_path(repo) do
    with false <- Mix.Project.umbrella?,
         path = Path.join(source_repo_priv(repo), "migrations"),
         false <- File.dir?(path),
         do: raise_missing_migrations(Path.relative_to_cwd(path), repo)
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
  Returns the private repository path relative to the source.
  """
  def source_repo_priv(repo) do
    config = repo.config()
    priv = config[:priv] || "priv/#{repo |> Module.split |> List.last |> Macro.underscore}"
    app = Keyword.fetch!(config, :otp_app)
    Path.join(Mix.Project.deps_paths[app] || File.cwd!, priv)
  end
end