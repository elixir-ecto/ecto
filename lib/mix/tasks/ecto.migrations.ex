defmodule Mix.Tasks.Ecto.Migrations do
  use Mix.Task
  import Mix.Ecto
  import Mix.EctoSQL

  @shortdoc "Displays the repository migration status"

  @moduledoc """
  Displays the up / down migration status for the given repository.

  The repository must be set under `:ecto_repos` in the
  current app configuration or given via the `-r` option.

  By default, migrations are expected at "priv/YOUR_REPO/migrations"
  directory of the current application but it can be configured
  by specifying the `:priv` key under the repository configuration.

  If the repository has not been started yet, one will be
  started outside our application supervision tree and shutdown
  afterwards.

  ## Examples

      mix ecto.migrations
      mix ecto.migrations -r Custom.Repo

  ## Command line options

    * `-r`, `--repo` - the repo to obtain the status for

  """

  @doc false
  def run(args, migrations \\ &Ecto.Migrator.migrations/1, puts \\ &IO.puts/1) do
    repos = parse_repo(args)

    result =
      Enum.map(repos, fn repo ->
        ensure_repo(repo, args)
        ensure_migrations_path(repo)
        {:ok, pid, _} = ensure_started(repo, all: true)

        repo_status = migrations.(repo)

        pid && repo.stop(pid)

        """

        Repo: #{inspect(repo)}

          Status    Migration ID    Migration Name
        --------------------------------------------------
        """ <>
          Enum.map_join(repo_status, "\n", fn {status, number, description} ->
            "  #{format(status, 10)}#{format(number, 16)}#{description}"
          end) <> "\n"
      end)

    puts.(Enum.join(result, "\n"))
  end

  defp format(content, pad) do
    content
    |> to_string
    |> String.pad_trailing(pad)
  end
end
