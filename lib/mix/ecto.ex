defmodule Mix.Ecto do
  @moduledoc """
  Conveniences for writing Ecto related Mix tasks.
  """

  @doc """
  Parses the repository option from the given command line args list.

  If no repo option is given, it is retrieved from the application environment.
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
      if apps_paths = Mix.Project.apps_paths() do
        Enum.filter(Mix.Project.deps_apps(), &is_map_key(apps_paths, &1))
      else
        [Mix.Project.config()[:app]]
      end

    apps
    |> Enum.flat_map(fn app ->
      Application.load(app)
      Application.get_env(app, :ecto_repos, [])
    end)
    |> Enum.uniq()
    |> case do
      [] ->
        Mix.shell().error """
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
  Ensures the given module is an Ecto.Repo.
  """
  @spec ensure_repo(module, list) :: Ecto.Repo.t
  def ensure_repo(repo, args) do
    # Do not pass the --force switch used by some tasks downstream
    args = List.delete(args, "--force")
    Mix.Task.run("app.config", args)

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
  Asks if the user wants to open a file based on ECTO_EDITOR.

  By default, it attempts to open the file and line using the
  `file:line` notation. For example, if your editor is called
  `subl`, it will open the file as:

      subl path/to/file:line

  It is important that you choose an editor command that does
  not block nor that attempts to run an editor directly in the
  terminal. Command-line based editors likely need extra
  configuration so they open up the given file and line in a
  separate window.

  Custom editors are supported by using the `__FILE__` and
  `__LINE__` notations, for example:

      ECTO_EDITOR="my_editor +__LINE__ __FILE__"

  and Elixir will properly interpolate values.

  """
  @spec open?(binary, non_neg_integer) :: boolean
  def open?(file, line \\ 1) do
    editor = System.get_env("ECTO_EDITOR") || ""

    if editor != "" do
      command =
        if editor =~ "__FILE__" or editor =~ "__LINE__" do
          editor
          |> String.replace("__FILE__", inspect(file))
          |> String.replace("__LINE__", Integer.to_string(line))
        else
          "#{editor} #{inspect(file)}:#{line}"
        end

      Mix.shell().cmd(command)
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
    if Mix.Project.umbrella?() do
      Mix.raise "Cannot run task #{inspect task} from umbrella project root. " <>
                  "Change directory to one of the umbrella applications and try again"
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
