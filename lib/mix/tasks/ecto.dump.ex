defmodule Mix.Tasks.Ecto.Dump do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Dumps the repository database structure"
  @default_opts [quiet: false]

  @aliases [
    d: :dump_path,
    q: :quiet
  ]

  @switches [
    dump_path: :string,
    quiet: :boolean
  ]

  @moduledoc """
  Dumps the current environment's database structure for the
  given repository into a structure file.

  The repository must be set under `:ecto_repos` in the
  current app configuration or given via the `-r` option.

  This task needs some shell utility to be present on the machine running the task.

   Database   | Utility needed
   :--------- | :-------------
   PostgreSQL | pg_dump
   MySQL      | mysqldump

  ## Example

      mix ecto.dump

  ## Command line options

    * `-r`, `--repo` - the repo to load the structure info from
    * `-d`, `--dump-path` - the path of the dump file to create
    * `-q`, `--quiet` - run the command quietly
  """

  def run(args) do
    {opts, _, _} =
      OptionParser.parse args, switches: @switches, aliases: @aliases

    opts = Keyword.merge(@default_opts, opts)

    Enum.each parse_repo(args), fn repo ->
      ensure_repo(repo, args)
      ensure_implements(repo.__adapter__, Ecto.Adapter.Structure,
                                          "dump structure for #{inspect repo}")
      config = Keyword.merge(repo.config, opts)

      case repo.__adapter__.structure_dump(source_repo_priv(repo), config) do
        {:ok, location} ->
          unless opts[:quiet] do
            Mix.shell.info "The structure for #{inspect repo} has been dumped to #{location}"
          end
        {:error, term} when is_binary(term) ->
          Mix.raise "The structure for #{inspect repo} couldn't be dumped: #{term}"
        {:error, term} ->
          Mix.raise "The structure for #{inspect repo} couldn't be dumped: #{inspect term}"
      end
    end
  end
end
