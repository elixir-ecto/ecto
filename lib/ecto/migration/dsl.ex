defmodule Ecto.Migration.DSL do
  @moduledoc """
  Functions and macros for defining migration operations.
  """
  alias Ecto.Migration.Table
  alias Ecto.Migration.Index
  alias Ecto.Migration.Runner

  @doc """
  Creates a table.

  ## Examples

      create table(:posts) do
        add :title, :string, default: "Untitled"
        add :body,  :text

        timestamps
      end

  """
  defmacro create(object, do: block) do
    commands = case block do
      {:__block__, _location, ops} -> ops
      _ -> [block]
    end

    quote(location: :keep) do
      %Table{key: key} = unquote(object)
      id = if key, do: [add(:id, :primary_key)], else: []
      execute {:create, unquote(object), id ++ unquote(commands) |> List.flatten}
    end
  end

  @doc """
  Alters a table.

  ## Examples

      alter table(:posts) do
        add :summary, :text
        modify :title, :text
        remove :views
        rename :slug, :permalink
      end

  """
  defmacro alter(object, do: block) do
    commands = case block do
      {:__block__, _location, ops} -> ops
      _ -> [block]
    end

    quote(location: :keep) do
      execute {:alter, unquote(object), unquote(commands) |> List.flatten}
    end
  end

  def create(object) do
    execute {:create, object}
  end

  @doc """
  Drops a table or index.

  ## Examples

      drop index(:posts, [:name])
      drop table(:posts)

  """
  def drop(object) do
    execute {:drop, object}
  end

  def table(name, opts \\ []) do
    %Table{name: name, key: Dict.get(opts, :key, true)}
  end

  def index(columns, opts=[on: table]) do
    %Index{table: table, columns: columns, unique: opts[:unique]}
  end

  def index(table, columns, opts \\ []) do
    %Index{table: table, columns: columns, unique: opts[:unique]}
  end

  @doc """
  Executes arbitrary SQL.

  ## Examples

    execute "UPDATE posts SET published_at = NULL"

  """
  def execute(command) do
    Runner.execute command
  end

  @doc """
  Add a column when creating or altering a table.

  ## Examples

      create table(:posts) do
        add :title, :string, default: "Untitled"
      end

      alter table(:posts) do
        add :summary, :text
      end

  """
  def add(column, type, opts \\ []) do
    {:add, column, type, opts}
  end

  @doc """
  Modify a column when altering a table.

  ## Examples

      alter table(:posts) do
        modify :title, :text
      end

  """
  def modify(column, type, opts \\ []) do
    {:modify, column, type, opts}
  end

  @doc """
  Remove a column when altering a table.

  ## Examples

      alter table(:posts) do
        remove :title
      end

  """
  def remove(column) do
    {:remove, column}
  end

  @doc """
  Rename a column when altering a table.

  ## Examples

      alter table(:posts) do
        rename :name, :title
      end

  """
  def rename(from, to) do
    {:rename, from, to}
  end

  @doc """
  Adds `created_at` and `updated_at` columns to a table.

  ## Examples

      create table(:posts) do
        timestamps
      end

  """
  def timestamps do
    [add(:created_at, :datetime), add(:updated_at, :datetime)]
  end

  @doc """
  Adds a foreign key.

  ## Examples

      create table(:product) do
        add :category_id, references(:category)
      end

  ## Options

  `:foreign_column` - The foreign column's name, default is `:id`;
  `:type` - The foreign column's type, default is `:integer`;

  """
  def references(table, opts \\ []) do
    foreign_column = Keyword.get(opts, :foreign_column, :id)
    type           = Keyword.get(opts, :type, :integer)

    {:references, table, foreign_column, type}
  end
end
