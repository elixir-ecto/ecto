defmodule Mix.Tasks.Ecto.Create do
  use Mix.Task
  import Mix.Tasks.Ecto

  @shortdoc "Create the database for the repo"

  @moduledoc """
  Create the database for the given repository, as specified in the repo's `url`.

  ## Command line options

  * `--no-start` - do not start applications

  ## Examples

      mix ecto.create MyApp.Repo

  """
  def run(args) do
    Mix.Task.run "app.start", args

    {repo, _} = parse_repo(args)
    ensure_repo(repo)
    ensure_implements(repo.adapter, Ecto.Adapter.Storage, "to create storage for #{inspect repo}")

    case Ecto.Storage.up(repo) do
      :ok ->
        Mix.shell.info "The database for repo #{inspect repo} has been created."
      {:error, :already_up} ->
        Mix.shell.info "The database for repo #{inspect repo} has already been created."
      {:error, term} ->
        raise Mix.Error, message:
           "The database for repo #{inspect repo} couldn't be created, reason given: #{term}."
    end
  end
end
