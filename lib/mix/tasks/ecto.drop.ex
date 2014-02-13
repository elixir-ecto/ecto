defmodule Mix.Tasks.Ecto.Drop do
  use Mix.Task
  import Mix.Tasks.Ecto

  @shortdoc "Drop the database for the repo"

  @moduledoc """
  Drop the database for the given repository, as specified in the repo's `url`.

  ## Command line options

  * `--no-start` - do not start applications

  ## Examples

      mix ecto.drop MyApp.Repo

  """
  def run(args) do
    Mix.Task.run "app.start", args

    { repo, _ } = parse_repo(args)
    ensure_repo(repo)
    ensure_storage_down(repo)

    case repo.storage_down do
      :ok ->
        Mix.shell.info "The database for repo #{inspect repo} has been dropped."
      { :error, :already_down } ->
        Mix.shell.info "The database for repo #{inspect repo} has already been dropped."
      { :error, term } ->
        raise Mix.Error, message:
           "The database for repo #{inspect repo} couldn't be dropped, reason given: #{term}."
    end
  end

  defp ensure_storage_down(repo) do
    Code.ensure_loaded(repo.adapter)
    unless function_exported?(repo.adapter, :storage_down, 1) do
      raise Mix.Error, message: "Expected #{inspect repo.adapter} to define storage_down/1 in order to drop #{inspect repo}."
    end
  end
end
