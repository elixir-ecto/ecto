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
    repos = parse_repo(args)
    ensure_repo(repos, args)

    Enum.all?(repos, &ensure_implements(&1.__adapter__, Ecto.Adapter.Storage,
                                        "to drop storage for #{inspect &1}"))

    {opts, _, _} = OptionParser.parse args, switches: [quiet: :boolean]

    Enum.each repos, fn repo ->
      if skip_safety_warnings?() or
         Mix.shell.yes?("Are you sure you want to drop the database for repo #{inspect repo}?") do
        drop_database(repo, opts)
      end
    end
  end

  defp skip_safety_warnings? do
    Mix.Project.config[:start_permanent] != true
  end

  defp drop_database(repo, opts) do
    case Ecto.Storage.down(repo) do
      :ok ->
        unless opts[:quiet] do
          Mix.shell.info "The database for #{inspect repo} has been dropped."
        end
      {:error, :already_down} ->
        unless opts[:quiet] do
          Mix.shell.info "The database for #{inspect repo} has already been dropped."
        end
      {:error, term} when is_binary(term) ->
        Mix.raise "The database for #{inspect repo} couldn't be dropped, reason given: #{term}."
      {:error, term} ->
        Mix.raise "The database for #{inspect repo} couldn't be dropped, reason given: #{inspect term}."
    end
  end
end
