defmodule Mix.Tasks.Ecto.Drop do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Drops the repository storage"
  @default_opts [force: false]

  @moduledoc """
  Drop the storage for the given repository.

  The repositories to create are the ones specified under the
  `:ecto_repos` option in the current app configuration. However,
  if the `-r` option is given, it replaces the `:ecto_repos` config.

  Since Ecto tasks can only be executed once, if you need to create
  multiple repositories, set `:ecto_repos` accordingly or pass the `-r`
  flag multiple times.

  ## Examples

      mix ecto.drop
      mix ecto.drop -r Custom.Repo

  ## Command line options

    * `-r`, `--repo` - the repo to drop
    * `--no-compile` - do not compile before stopping
    * `--force` - do not ask for confirmation

  """

  @doc false
  def run(args) do
    repos = parse_repo(args)
    {opts, _, _} = OptionParser.parse args, switches: [quiet: :boolean, force: :boolean]
    opts = Keyword.merge(@default_opts, opts)

    Enum.each repos, fn repo ->
      ensure_repo(repo, args)
      ensure_implements(repo.__adapter__, Ecto.Adapter.Storage,
                                          "drop storage for #{inspect repo}")

      if skip_safety_warnings?() or
         opts[:force] or
         Mix.shell.yes?("Are you sure you want to drop the database for repo #{inspect repo}?") do
        drop_database(repo, opts)
      end
    end
  end

  defp skip_safety_warnings? do
    Mix.Project.config[:start_permanent] != true
  end

  defp drop_database(repo, opts) do
    case repo.__adapter__.storage_down(repo.config) do
      :ok ->
        unless opts[:quiet] do
          Mix.shell.info "The database for #{inspect repo} has been dropped"
        end
      {:error, :already_down} ->
        unless opts[:quiet] do
          Mix.shell.info "The database for #{inspect repo} has already been dropped"
        end
      {:error, term} when is_binary(term) ->
        Mix.raise "The database for #{inspect repo} couldn't be dropped: #{term}"
      {:error, term} ->
        Mix.raise "The database for #{inspect repo} couldn't be dropped: #{inspect term}"
    end
  end
end
