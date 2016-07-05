defmodule Mix.Tasks.Ecto.Load do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Loads previously dumped database structure"
  @recursive true

  @moduledoc """
  Loads the current environment's database structure for the
  given repository from a previously dumped structure file.

  The repository must be set under `:ecto_repos` in the
  current app configuration or given via the `-r` option.

  ## Example

      mix ecto.load

  ## Command line options

    * `-r`, `--repo` - the repo to load the structure info into
    * `-d`, `--dump-path` - the path of the dump file to load from
  """

  def run(args) do
    {opts, _, _} =
      OptionParser.parse args, switches: [dump_path: :string, quiet: :boolean], aliases: [d: :dump_path]

    Enum.each parse_repo(args), fn repo ->
      ensure_repo(repo, args)
      ensure_implements(repo.__adapter__, Ecto.Adapter.Structure,
                                          "to load structure for #{inspect repo}")
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
end
