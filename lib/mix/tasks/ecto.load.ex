defmodule Mix.Tasks.Ecto.Load do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Loads previously dumped database structure"
  @default_opts [force: false, quiet: false]

  @aliases [
    d: :dump_path,
    f: :force,
    q: :quiet
  ]

  @switches [
    dump_path: :string,
    force: :boolean,
    quiet: :boolean
  ]

  @moduledoc """
  Loads the current environment's database structure for the
  given repository from a previously dumped structure file.

  The repository must be set under `:ecto_repos` in the
  current app configuration or given via the `-r` option.

  This task needs some shell utility to be present on the machine running the task.

   Database   | Utility needed
   :--------- | :-------------
   PostgreSQL | psql
   MySQL      | mysql

  ## Example

      mix ecto.load

  ## Command line options

    * `-r`, `--repo` - the repo to load the structure info into
    * `-d`, `--dump-path` - the path of the dump file to load from
    * `-f`, `--force` - do not ask for confirmation
    * `-q`, `--quiet` - run the command quietly
  """

  def run(args) do
    {opts, _, _} =
      OptionParser.parse args, switches: @switches, aliases: @aliases

    opts = Keyword.merge(@default_opts, opts)

    Enum.each parse_repo(args), fn repo ->
      ensure_repo(repo, args)
      ensure_implements(repo.__adapter__, Ecto.Adapter.Structure,
                                          "load structure for #{inspect repo}")

      if skip_safety_warnings?() or
          opts[:force] or
          Mix.shell.yes?("Are you sure you want to load a new structure for #{inspect repo}? Any existing data in this repo may be lost.") do
        load_structure(repo, opts)
      end
    end
  end

  defp skip_safety_warnings? do
    Mix.Project.config[:start_permanent] != true
  end

  defp load_structure(repo, opts) do
    config = Keyword.merge(repo.config, opts)

    case repo.__adapter__.structure_load(source_repo_priv(repo), config) do
      {:ok, location} ->
        unless opts[:quiet] do
          Mix.shell.info "The structure for #{inspect repo} has been loaded from #{location}"
        end
      {:error, term} when is_binary(term) ->
        Mix.raise "The structure for #{inspect repo} couldn't be loaded: #{term}"
      {:error, term} ->
        Mix.raise "The structure for #{inspect repo} couldn't be loaded: #{inspect term}"
    end
  end
end
