defmodule Mix.Tasks.Ecto.Create do
  use Mix.Task
  import Mix.Tasks.Ecto

  @shortdoc "Create a Repo"

  @moduledoc """
  Create the given repository in the location specified at its `url`.

  ## Examples

      mix ecto.create MyApp.Repo

  """
  def run(args) do
    { repo, _ } = parse_repo(args)
    ensure_repo(repo)
    ensure_storage_up(repo)

    case repo.adapter.storage_up(repo) do
      :ok ->
        Mix.shell.info "The repo #{inspect repo} has been created."
      { :error, :already_up } ->
        Mix.shell.info "The repo #{inspect repo} is already up."
      { :error, term } ->
        raise Mix.Error, message:
           "The repo #{inspect repo} couldn't be started, reason given: #{term}."
    end
  end

  defp ensure_storage_up(repo) do
    unless function_exported?(repo.adapter, :storage_up, 1) do
      raise Mix.Error, message: "Expected #{inspect repo.adapter} to define storage_up/1 in order to create #{inspect repo}."
    end
  end
end
