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
    * `--no-compile` - do not compile before stopping

  """

  @doc false
  def run(args) do
    repo = parse_repo(args)
    ensure_repo(repo, args)
    ensure_implements(repo.__adapter__, Ecto.Adapter.Storage,
                      "to drop storage for #{inspect repo}")

    {opts, _, _} = OptionParser.parse args, switches: [quiet: :boolean]

    case Ecto.Storage.down(repo) do
      :ok ->
        unless opts[:quiet] do
          Mix.shell.info "The database for #{inspect repo} has been dropped."
        end
      {:error, :already_down} ->
        unless opts[:quiet] do
          Mix.shell.info "The database for #{inspect repo} has already been dropped."
        end
      {:error, term} ->
        Mix.raise "The database for #{inspect repo} couldn't be dropped, reason given: #{inspect term}."
    end
  end
end
