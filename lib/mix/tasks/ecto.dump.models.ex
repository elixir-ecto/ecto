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

  @mysql "mysql"
  @postgres "postgres"
  @template ~s"""
defmodule <%= app <> "." <> table  %> do
  use Ecto.Model

  schema "<%= table %>" do<%= for column <- columns do %>
    field :<%= String.downcase(elem(column,0)) %>, <%= elem(column, 1) %><%= if elem(column, 2) do %>, primary_key: true<% end %><% end %>
  end
end
"""

  @doc false
  def run(args) do
    repos = parse_repo(args)

    Enum.each repos, fn repo ->
      ensure_repo(repo, [])
      ensure_started(repo, [])

      driver = repo.__adapter__
        |> Atom.to_string
        |> String.downcase
        |> String.split(".")
        |> List.last
      IO.puts driver

      generate_models(driver, repo)
    end
  end

  def generate_models(driver, repo) when driver == @mysql do
    with config <- repo.config,
      true <- Keyword.keyword?(config),
      {:ok, database} <- Keyword.fetch(config, :database)
    do
        {:ok, result} = repo.query("SELECT table_name FROM information_schema.tables WHERE table_schema = '#{database}'")
        Enum.each result.rows, fn [table] ->
          {:ok, description} = repo.query("SELECT COLUMN_NAME, DATA_TYPE, CASE WHEN `COLUMN_KEY` = 'PRI' THEN '1' ELSE NULL END AS primary_key FROM information_schema.columns WHERE table_name= '#{table}' and table_schema='#{database}'")
          columns = Enum.map description.rows, fn [column_name, column_type, is_primary] ->
            {column_name, get_type(column_type), is_primary}
          end
          table = to_camelcase(table)
          content = EEx.eval_string(@template, [
            app: "name",
            table: table,
            columns: columns
          ])
          write_model(repo, table, content)
        end
    end
  end


  def generate_models(driver, repo) when driver == @postgres do
    {:ok, result} = repo.query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")
    Enum.each result.rows, fn [table] ->
      {:ok, primary_keys} = repo.query("SELECT c.column_name FROM information_schema.table_constraints tc JOIN information_schema.constraint_column_usage AS ccu USING (constraint_schema, constraint_name) JOIN information_schema.columns AS c ON c.table_schema = tc.constraint_schema AND tc.table_name = c.table_name AND ccu.column_name = c.column_name where constraint_type = 'PRIMARY KEY' and tc.table_name = '#{table}'")
      {:ok, description} = repo.query("SELECT column_name, data_type FROM information_schema.columns WHERE table_name ='#{table}'")
      columns = Enum.map description.rows, fn [column_name, column_type] ->
        found = Enum.find(List.flatten(primary_keys.rows), {:not_found}, fn x -> x == column_name end)
        case found do
          {:not_found} -> {column_name, get_type(List.first(String.split(String.downcase(column_type)))), nil}
          _ -> {column_name, get_type(column_type), true}
        end
      end
      table = to_camelcase(table)
      content = EEx.eval_string(@template, [
        app: "name",
        table: table,
        columns: columns
      ])
      write_model(repo, table, content)
    end
  end

  def generate_models(driver, repo) do
    IO.puts "#{driver} is not yet implemented inspect #{repo}"
  end

  defp write_model(repo, table, content) do
    filename = source_repo_priv(repo) <> "/" <> table <> ".ex"
    File.rm filename
    {:ok, file} = File.open(filename, [:write])
    IO.binwrite file, content
    File.close(file)

    IO.puts "\e[0;31m  #{filename} was generated"
  end

  defp to_camelcase(table_name) do
    Enum.map_join(String.split(table_name, "_"), "", &String.capitalize(&1))
  end

  defp get_type(row) do
    case row do
      type when type in ["int", "integer", "bigint", "mediumint", "smallint", "tinyint"] ->
        ":integer"
      type when type in ["varchar", "text", "char", "year", "mediumtext", "longtext", "tinytext", "enum", "character", "array"] ->
        ":string"
      type when type in ["decimal", "float", "double", "real"] ->
        ":float"
      type when type in ["boolean", "bit", "bit varying"] ->
        ":boolean"
      type when type in ["date"] ->
        ":date"
      type when type in ["datetime", "timestamp"] ->
        ":datetime"
      type when type in ["time"] ->
        ":time"
      type when type in ["blob"] ->
        ":binary"
    end
  end
end
