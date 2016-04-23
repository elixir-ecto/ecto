defmodule Mix.Tasks.Ecto.Load do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Loads the current environment's database structure from a previously dumped structure file"

  @moduledoc """
  Loads the current environment's database structure from a previously dumped structure file

  ## Example

      mix ecto.load

  ## Command line options

    * `-r`, `--repo` - the repo to load the structure info into.
    * `-f`, `--file` - the path of the file to load from. Will default to `{priv_dir(repo)}/structure.sql`
  """

  def run(args \\ []) do
    no_umbrella!("ecto.load")

    [repo] = parse_repo(args)
    ensure_repo(repo, args)

    path = parse_file(args, repo)

    structure_load(repo, path)
  end
end
