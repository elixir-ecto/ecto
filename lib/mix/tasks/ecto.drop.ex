defmodule Mix.Tasks.Ecto.Drop do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Drop the storage for the repo"

  @moduledoc """
  Drop the storage for the repository.

  ## Examples

      mix ecto.drop
      mix ecto.drop -r Custom.Repo

  ## Command line options

    * `-r`, `--repo` - the repo to drop (defaults to `YourApp.Repo`)
    * `--no-start` - do not start applications

  """

  @doc false
  def run(args) do
    Mix.Task.run "app.start", args

    repo = parse_repo(args)
    ensure_repo(repo)
    ensure_implements(repo.adapter, Ecto.Adapter.Storage, "to create storage for #{inspect repo}")

    case Ecto.Storage.down(repo) do
      :ok ->
        Mix.shell.info "The database for repo #{inspect repo} has been dropped."
      {:error, :already_down} ->
        Mix.shell.info "The database for repo #{inspect repo} has already been dropped."
      {:error, term} ->
        Mix.raise "The database for repo #{inspect repo} couldn't be dropped, reason given: #{term}."
    end
  end
end
