defmodule Mix.Tasks.Ecto.Migrate do
  use Mix.Task

  @moduledoc """
  Mix tasks for executing database migrations. 
  Expects repository as argument.
  
  ## Examples

      mix ecto.migrate MyApp.Repo
  """

  def run([repo]) do
    repository = case is_atom(repo) do
        true -> 
            repo
        false -> 
            binary_to_atom(repo, :utf8)
    end

    case Code.ensure_loaded(repository) do
      {:error, err} ->
        raise Ecto.MigrationCodeLoadError, err: err, repo: repository
      _ ->
        case List.keyfind(repository.__info__(:functions), :priv, 0) do
          {:priv, 0} ->
            Ecto.Migrator.run_up(repository, Path.absname(Path.join(repo.priv, "migrations")))
          _ -> 
            raise Ecto.MigrationPrivError, repo: repo
        end
    end
  end

end