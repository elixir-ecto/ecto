defmodule Mix.Tasks.Ecto.Dump.Models do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Dump models from repos"
  @recursive true

  @moduledoc """
  Dump models from repos

  The repository must be set under `:ecto_repos` in the
  current app configuration or given via the `-r` option.

  ## Examples

      mix ecto.dump.models

  ## Command line options

    * `-r`, `--repo` - the repo to create
  """


  @doc false
  def run(args) do
    repos = parse_repo(args)

    Enum.each repos, fn repo ->
      ensure_repo(repo, [])
      IO.puts repo

      driver = repo.__adapter__
        |> Atom.to_string 
        |> String.downcase
        |> String.split(".")
        |> List.last 
  
      process(driver, repo)
    end
  end

  defp process(driver, repo) when driver == "mysql" do
    IO.puts "process::mysql"
    IO.inspect repo.module_info
  end 

  defp process(driver, repo) when driver == "progresql" do
    IO.puts "process::progresql"
    IO.inspect repo.module_info
  end 


end
