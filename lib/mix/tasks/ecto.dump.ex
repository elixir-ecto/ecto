defmodule Mix.Tasks.Ecto.Dump do
  use Mix.Task
  import Mix.Ecto

  @recursive true
  @shortdoc "Dumps database structure"

  @moduledoc """
  Dumps the current environment's database structure into a structure file

  ## Example

      mix ecto.dump

  ## Command line options

    * `-r`, `--repo` - the repo to load the structure info from
    * `-d`, `--dump-path` - the path of the dump file to create
  """

  def run(args) do
    {opts, _, _} =
      OptionParser.parse args, switches: [dump_path: :string, quiet: :boolean], aliases: [d: :dump_path]

    Enum.each parse_repo(args), fn repo ->
      ensure_repo(repo, args)
      ensure_implements(repo.__adapter__, Ecto.Adapter.Structure,
                                          "to dump structure for #{inspect repo}")
      config = Keyword.merge(repo.config, opts)

      case repo.__adapter__.structure_dump(repo_priv(repo), config) do
        :ok ->
          unless opts[:quiet] do
            Mix.shell.info "The structure for #{inspect repo} has been dumped"
          end
        {:error, term} when is_binary(term) ->
          Mix.raise "The structure for #{inspect repo} couldn't be dumped: #{term}"
        {:error, term} ->
          Mix.raise "The structure for #{inspect repo} couldn't be dumped: #{inspect term}"
      end
    end
  end
end
