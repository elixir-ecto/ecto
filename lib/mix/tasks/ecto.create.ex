defmodule Mix.Tasks.Ecto.Create do
  use Mix.Task
  import Mix.Tasks.Ecto

  @shortdoc "Create the database for the repo"

  @moduledoc """
  Create the database for the given repository, as specified in the repo's `url`.

  ## Examples

      mix ecto.create MyApp.Repo

  """
  def run(args) do
    { repo, _ } = parse_repo(args)
    ensure_repo(repo)
    ensure_storage_up(repo)

    case repo.storage_up do
      :ok ->
        Mix.shell.info "The database for repo #{inspect repo} has been created."
      { :error, :already_up } ->
        Mix.shell.info "The database for repo #{inspect repo} has already been created."
      { :error, term } ->
        raise Mix.Error, message:
           "The database for repo #{inspect repo} couldn't be created, reason given: #{term}."
    end
  end

  defp ensure_storage_up(repo) do
    unless function_exported?(repo.adapter, :storage_up, 1) do
      raise Mix.Error, message: "Expected #{inspect repo.adapter} to define storage_up/1 in order to create #{inspect repo}."
    end
  end
end
