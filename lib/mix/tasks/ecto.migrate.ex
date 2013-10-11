defmodule Mix.Tasks.Ecto.Migrate do
  use Mix.Task

  @moduledoc """
  Mix tasks for executing database migrations. 
  Expects repository as argument.
  
  ## Examples

      mix ecto.migrate MyApp.Repo
  """

  def run([repo]) do
    repository = if is_atom(repo) do
      repo
    else 
      binary_to_atom(repo, :utf8)
    end

    case Code.ensure_loaded(repository) do
      {:error, err} ->
        raise Mix.Error, message: 
        """
        Migration module `#{repository}` loading error: #{err}
        """
      _ ->   
        case function_exported?(repository, :priv, 0) do
          true ->
            Ecto.Migrator.run_up(repository, Path.absname(Path.join(repo.priv, "migrations")))
          false -> 
            raise Mix.Error, message: 
            """
            A repository #{repo} needs to implement the priv/0 function.
            """
        end
    end
  end
end