defmodule Mix.Tasks.Ecto.Create do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Creates the repository storage"

  @moduledoc """
  Create the storage for the given repository.

  The repositories to create are the ones specified under the
  `:ecto_repos` option in the current app configuration. However,
  if the `-r` option is given, it replaces the `:ecto_repos` config.

  Since Ecto tasks can only be executed once, if you need to create
  multiple repositories, set `:ecto_repos` accordingly or pass the `-r`
  flag multiple times.

  ## Examples

      mix ecto.create
      mix ecto.create -r Custom.Repo

  ## Command line options

    * `-r`, `--repo` - the repo to create
    * `--no-compile` - do not compile before creating
    * `--quiet` - do not log output

  """

  @doc false
  def run(args) do
    repos = parse_repo(args)
    {opts, _, _} = OptionParser.parse args, switches: [quiet: :boolean]

    Enum.each repos, fn repo ->
      ensure_repo(repo, args)
      ensure_implements(repo.__adapter__, Ecto.Adapter.Storage,
                                          "create storage for #{inspect repo}")
      case repo.__adapter__.storage_up(repo.config) do
        :ok ->
          unless opts[:quiet] do
            Mix.shell.info "The database for #{inspect repo} has been created"
          end
        {:error, :already_up} ->
          unless opts[:quiet] do
            Mix.shell.info "The database for #{inspect repo} has already been created"
          end
        {:error, term} when is_binary(term) ->
          Mix.raise "The database for #{inspect repo} couldn't be created: #{term}"
        {:error, term} ->
          Mix.raise "The database for #{inspect repo} couldn't be created: #{inspect term}"
      end
    end
  end
end
