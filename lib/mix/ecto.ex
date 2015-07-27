defmodule Mix.Ecto do
  # Conveniences for writing Mix.Tasks in Ecto.
  @moduledoc false

  @doc """
  Parses the repository option from the given list.

  If no repo option is given, we get one from the environment.
  """
  @spec parse_repo([term]) :: Ecto.Repo.t
  def parse_repo([key, value|_]) when key in ~w(--repo -r) do
    Module.concat([value])
  end

  def parse_repo([_|t]) do
    parse_repo(t)
  end

  def parse_repo([]) do
    app = Mix.Project.config |> Keyword.fetch!(:app)

    case Application.get_env(app, :app_namespace, app) do
      ^app -> app |> to_string |> Mix.Utils.camelize
      mod  -> mod |> inspect
    end |> Module.concat(Repo)
  end

  @doc """
  Ensures the given module is a repository.
  """
  @spec ensure_repo(module, list) :: Ecto.Repo.t | no_return
  def ensure_repo(repo, args) do
    Mix.Task.run "loadpaths", args

    unless "--no-compile" in args do
      # TODO: Use Mix.Project.compile(args) with v1.1
      Mix.Task.run "compile", args
    end

    case Code.ensure_compiled(repo) do
      {:module, _} ->
        if function_exported?(repo, :__repo__, 0) do
          repo
        else
          Mix.raise "module #{inspect repo} is not a Ecto.Repo. " <>
                    "Please pass a proper repo with the -r option."
        end
      {:error, error} ->
        Mix.raise "could not load #{inspect repo}, error: #{inspect error}. " <>
                  "Please pass a proper repo with the -r option."
    end
  end

  @doc """
  Ensures the given repository is started and running.
  """
  @spec ensure_started(Ecto.Repo.t) :: Ecto.Repo.t | no_return
  def ensure_started(repo) do
    {:ok, _} = Application.ensure_all_started(:ecto)

    case repo.start_link do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _}} -> {:ok, nil}
      {:error, error} ->
        Mix.raise "could not start repo #{inspect repo}, error: #{inspect error}"
    end
  end

  @doc """
  Ensure the repository is stopped.
  """
  @spec ensure_stopped(pid | nil) :: :ok
  def ensure_stopped(nil), do: :ok
  def ensure_stopped(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :normal)
    receive do
      {:DOWN, ^ref, _, _, _} ->
        :ok
    after
      30_000 ->
        Mix.raise "repository did not shutdown after running command"
    end
  end

  @doc """
  Gets the migrations path from a repository.
  """
  @spec migrations_path(Ecto.Repo.t) :: String.t
  def migrations_path(repo) do
    Path.join(repo_priv(repo), "migrations")
  end

  @doc """
  Returns the private repository path.
  """
  def repo_priv(repo) do
    config = repo.config()

    Application.app_dir(Keyword.fetch!(config, :otp_app),
      config[:priv] || "priv/#{repo |> Module.split |> List.last |> Mix.Utils.underscore}")
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
      Mix.raise "cannot run task #{inspect task} from umbrella application"
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
