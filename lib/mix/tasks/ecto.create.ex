defmodule Mix.Tasks.Ecto.Create do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Create the storage for the repo"

  @moduledoc """
  Create the storage for the repository.

  ## Examples

      mix ecto.create
      mix ecto.create -r Custom.Repo

  ## Command line options

    * `-r`, `--repo` - the repo to create (defaults to `YourApp.Repo`)
    * `--no-start` - do not start applications

  """

  @doc false
  def run(args) do
    Mix.Task.run "app.start", args

    repo = parse_repo(args)
    ensure_repo(repo)
    ensure_implements(repo.adapter, Ecto.Adapter.Storage, "to create storage for #{inspect repo}")

    case Ecto.Storage.up(repo) do
      :ok ->
        Mix.shell.info "The database for repo #{inspect repo} has been created."
      {:error, :already_up} ->
        Mix.shell.info "The database for repo #{inspect repo} has already been created."
      {:error, term} ->
        Mix.raise "The database for repo #{inspect repo} couldn't be created, reason given: #{term}."
    end
  end
end
