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
    quote(location: :keep) do
      %Table{key: key} = unquote(object)
      Runner.start_command({:create, unquote(object)})

      if key do
        add(:id, :primary_key)
      end

      unquote(block)
      Runner.end_command
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
    quote(location: :keep) do
      Runner.start_command({:alter, unquote(object)})
      unquote(block)
      Runner.end_command
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

  @doc """
  Returns a `%Table{}`.

  ## Examples

      create table(:products) do
        add :name, :string
        add :price, :decimal
      end

      alter table(:products) do
        rename :name, :title
      end

      drop table(:products)
  """
  def table(name, opts \\ []) do
    %Table{name: name, key: Dict.get(opts, :key, true)}
  end

  @doc """
  Returns a `%Index{}`. Indexes are non-unique by default.

  ## Examples

      create index(:products, [:category_id, :sku], unique: true)

      drop index(:products, [:category_id, :sku])
  """
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

  ## Options

  * `:default` The column's default value.
  * `:null` `false` if the column should not allow null values.
  * `:size` The size of the type. For example the numbers of characters. Default is no size.

  """
  def add(column, type, opts \\ []) do
    Runner.add_element {:add, column, type, opts}
  end

  @doc """
  Modify a column when altering a table.

  ## Examples

      alter table(:posts) do
        modify :title, :text
      end

  ## Options

  * `:default` The column's default value.
  * `:null` `false` if the column should not allow null values.
  * `:size` The size of the type. For example the numbers of characters. Default is no size.
  """
  def modify(column, type, opts \\ []) do
    Runner.add_element {:modify, column, type, opts}
  end

  @doc """
  Remove a column when altering a table.

  ## Examples

      alter table(:posts) do
        remove :title
      end

  """
  def remove(column) do
    Runner.add_element {:remove, column}
  end

  @doc """
  Rename a column when altering a table.

  ## Examples

      alter table(:posts) do
        rename :name, :title
      end

  """
  def rename(from, to) do
    Runner.add_element {:rename, from, to}
  end

  @doc """
  Adds `created_at` and `updated_at` columns to a table.

  ## Examples

      create table(:posts) do
        timestamps
      end

  """
  def timestamps do
    add(:created_at, :datetime)
    add(:updated_at, :datetime)
  end

  @doc """
  Adds a foreign key.

  ## Examples

      create table(:product) do
        add :category_id, references(:category)
      end

  ## Options

  * `:foreign_column` The foreign column's name, default is `:id`
  * `:type`           The foreign column's type, default is `:integer`

  """
  def references(table, opts \\ []) do
    foreign_column = Keyword.get(opts, :foreign_column, :id)
    type           = Keyword.get(opts, :type, :integer)

    {:references, table, foreign_column, type}
  end

  @doc """
  Checks if a column exists.

  ## Examples

    if !column_exists?(:products, :name) do
      add_column(:products, :name, :string)
    end

  """
  def column_exists?(table_name, column_name) do
    exists?(:column, {table_name, column_name})
  end

  @doc """
  Checks if a table exists.

  ## Examples

    if table_exists?(:products) do
      drop table(:products)
    end

  """
  def table_exists?(table_name) do
    exists?(:table, table_name)
  end

  @doc """
  Checks if an index exists.

  ## Examples

    if index_exists?(:products_index) do
      drop index(:products_index)
    end

  """
  def index_exists?(name) do
    exists?(:index, name)
  end

  defp exists?(type, object) do
    Runner.exists?(type, object)
  end
end
