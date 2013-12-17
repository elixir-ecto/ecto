defmodule Mix.Tasks.Ecto do
  # Conveniences for writing Mix.Tasks in Ecto.
  @moduledoc false

  @doc """
  Parses the repository as the first argument in the given list
  and ensure the repository is loaded and available.
  """
  @spec parse_repo([term]) :: { Ecto.Repo.t, [term] } | no_return
  def parse_repo([h|t]) when is_binary(h) and h != "" do
    { Module.concat([h]), t }
  end

  def parse_repo([h|t]) when is_atom(h) and h != :"" do
    { h, t }
  end

  def parse_repo(_) do
    raise Mix.Error, message: "invalid arguments, expected a repo as first argument"
  end

  @doc """
  Ensures the given module is a repository.
  """
  @spec ensure_repo(module) :: Ecto.Repo.t | no_return
  def ensure_repo(repo) do
    case Code.ensure_compiled(repo) do
      { :module, _ } ->
        if function_exported?(repo, :__repo__, 0) do
          repo
        else
          raise Mix.Error, message: "module #{inspect repo} is not a Ecto.Repo, it does not define __repo__/0"
        end
      { :error, error } ->
        raise Mix.Error, message: "could not load #{inspect repo}, error: #{inspect error}"
    end
  end

  @doc """
  Ensures the given repository is started and running.
  """
  @spec ensure_started(Ecto.Repo.t) :: Ecto.Repo.t | no_return
  def ensure_started(repo) do
    case repo.start_link do
      :ok -> repo
      { :ok, _ } -> repo
      { :error, { :already_started, _ } } -> repo
      { :error, error } ->
        raise Mix.Error, message: "could not start repo #{inspect repo}, error: #{inspect error}"
    end
  end

  @doc """
  Gets the migrations path from a repository.
  """
  @spec migrations_path(Ecto.Repo.T) :: String.t | no_return
  def migrations_path(repo) do
    if function_exported?(repo, :priv, 0) do
      # Convert migrations path from _build to source.
      Path.join(Path.relative_to(repo.priv, Mix.Project.app_path), "migrations")
    else
      raise Mix.Error, message: "expected repo #{inspect repo} to define priv/0 in order to use migrations"
    end
  end

  @doc """
  Asks if the user wants to open a file based on ECTO_EDITOR.
  """
  @spec open?(binary) :: boolean
  def open?(file) do
    editor = System.get_env("ECTO_EDITOR") || ""
    if editor != "" do
      System.cmd editor <> " " <> inspect(file)
      true
    else
      false
    end
  end
end
