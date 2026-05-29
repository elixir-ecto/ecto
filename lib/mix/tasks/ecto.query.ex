defmodule Mix.Tasks.Ecto.Query do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Runs a query against the repository"

  @switches [
    limit: :integer,
    repo: [:string, :keep],
    no_compile: :boolean,
    no_deps_check: :boolean
  ]

  @aliases [
    r: :repo
  ]

  @moduledoc """
  Runs the given query against the repository.

  The query is evaluated as Elixir code after loading the current
  `.iex.exs` file, if one exists, and importing `Ecto.Query`.

  ## Examples

      $ mix ecto.query "from p in Post, where: p.published"
      $ mix ecto.query -r Custom.Repo "from p in Post, limit: 10"

  ## Command line options

    * `-r`, `--repo` - the repo to query
    * `--limit` - limits the number of printed entries. Defaults to 100.

  """

  @default_limit 100

  @impl true
  def run(args) do
    repos = parse_repo(args)
    {opts, query_args} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    repo =
      case repos do
        [repo] -> repo
        [] -> Mix.raise("ecto.query expects a repository to be configured or given as -r MyApp.Repo")
        [_ | _] -> Mix.raise("ecto.query found multiple repositories, please pass one with -r")
      end

    query =
      case query_args do
        [query] -> query
        [] -> Mix.raise("ecto.query expects a query to be given")
        [_ | _] -> Mix.raise("ecto.query expects a single query to be given")
      end

    limit = Keyword.get(opts, :limit, @default_limit)

    if limit < 0 do
      Mix.raise("ecto.query expects --limit to be greater than or equal to zero")
    end

    Mix.Task.run("app.start", args)
    ensure_repo(repo, args)

    query = eval_query(query)

    repo.transaction(
      fn ->
        query
        |> repo.all()
        |> Enum.take(limit)
      end,
      read_only: true
    )
    |> case do
      {:ok, entries} ->
        entries
        |> clean_entries()
        |> inspect(limit: :infinity, pretty: true)
        |> Mix.shell().info()

      {:error, reason} ->
        Mix.raise("ecto.query failed: #{inspect(reason)}")
    end
  end

  defp eval_query(query) do
    code = [dot_iex(), "\nimport Ecto.Query\n", query]

    {queryable, _binding} =
      code
      |> IO.iodata_to_binary()
      |> Code.eval_string([], file: "ecto.query")

    to_query!(queryable)
  end

  defp to_query!(queryable) do
    Ecto.Queryable.to_query(queryable)
  rescue
    Protocol.UndefinedError ->
      Mix.raise(
        "Expected ecto.query to evaluate to a queryable expression, got: #{inspect(queryable)}"
      )
  end

  defp dot_iex do
    if File.regular?(".iex.exs") do
      [File.read!(".iex.exs"), "\n"]
    else
      []
    end
  end

  defp clean_entries(entries) do
    Enum.map(entries, &clean_entry/1)
  end

  defp clean_entry(%{__struct__: schema} = struct) do
    if function_exported?(schema, :__schema__, 1) do
      drop_fields = [
        :__meta__ | schema.__schema__(:associations) ++ schema.__schema__(:redact_fields)
      ]

      fields =
        struct
        |> Map.from_struct()
        |> Map.drop(drop_fields)
        |> Enum.map(fn {key, value} -> {key, clean_entry(value)} end)
        |> Enum.sort()

      struct(Mix.Tasks.Ecto.Query.Schema, schema: schema, fields: fields)
    else
      struct
    end
  end

  defp clean_entry(entries) when is_list(entries), do: Enum.map(entries, &clean_entry/1)

  defp clean_entry(%{} = entry),
    do: Map.new(entry, fn {key, value} -> {key, clean_entry(value)} end)

  defp clean_entry(entry), do: entry
end

defmodule Mix.Tasks.Ecto.Query.Schema do
  @moduledoc false

  defstruct [:schema, :fields]
end

defimpl Inspect, for: Mix.Tasks.Ecto.Query.Schema do
  import Inspect.Algebra

  def inspect(%{schema: schema, fields: fields}, opts) do
    docs =
      Enum.map(fields, fn {key, value} ->
        concat([Atom.to_string(key), ": ", to_doc(value, opts)])
      end)

    container_doc("%#{inspect(schema)}{", docs, "}", opts, fn doc, _opts -> doc end)
  end
end
