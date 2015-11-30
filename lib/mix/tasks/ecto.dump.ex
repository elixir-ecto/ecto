defmodule Mix.Tasks.Ecto.Dump do
  use Mix.Task
  import Mix.Ecto
  import Mix.Generator

  @shortdoc "Dumps the current environment's database structure into a structure file"

  @moduledoc """
  Dumps the current environment's database structure into a structure file

  ## Example

      mix ecto.dump

  ## Command line options

    * `-r`, `--repo` - the repo to load the structure info into.
    * `-f`, `--file` - the path of the file to dump into. Will default to `{priv_dir(repo)}/structure.sql`
  """

  def run(args \\ []) do
    no_umbrella!("ecto.dump")

    [repo] = parse_repo(args)
    ensure_repo(repo, args)

    path = parse_file(args, repo)

    create_directory Path.dirname(path)
    create_file path, structure_dump(repo), force: true
  end
end
