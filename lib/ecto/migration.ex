defmodule Ecto.Migration do
  @moduledoc """
  Migrations are used to modify your database schema over time.

  This module provides many helpers for migrating the database,
  allowing developers to use Elixir to alter their storage in
  a way it is database independent.

  Here is an example:

      defmodule MyRepo.Migrations.CreatePosts do
        use Ecto.Migration

        def up do
          create table(:weather) do
            add :city,    :string, size: 40
            add :temp_lo, :integer
            add :temp_hi, :integer
            add :prcp,    :float
          end
        end

        def down do
          drop table(:weather)
        end
      end

  Note migrations have an `up/0` and `down/0` instructions, where
  `up/0` is used to update your database and `down/0` rolls back
  the prompted changes.

  Ecto provides some mix tasks to help developers work with migrations:

    * `mix ecto.gen.migration Repo add_weather_table` - generates a
      migration that the user can fill in with particular commands
    * `mix ecto.migrate Repo` - migrates a repository
    * `mix ecto.rollback Repo` - rolls back a particular migration

  Run the `mix help COMMAND` for more information.

  ## Change

  Migrations can also be automatically reversible by implementing
  `change/0` instead of `up/0` and `down/0`. For example, the
  migration above can be written as:

      defmodule MyRepo.Migrations.CreatePosts do
        use Ecto.Migration

        def change do
          create table(:weather) do
            add :city,    :string, size: 40
            add :temp_lo, :integer
            add :temp_hi, :integer
            add :prcp,    :float
          end
        end
      end

  Notice not all commands are reversible though. Trying to rollback
  a non-reversible command will raise an `Ecto.MigrationError`.
  """

  defmodule Index do
    @moduledoc """
    Defines an index struct used in migrations.
    """
    defstruct table: nil, name: nil, columns: [], unique: false
    @type t :: %__MODULE__{table: atom, name: atom, columns: [atom], unique: boolean}
  end

  defmodule Table do
    @moduledoc """
    Defines a table struct used in migrations.
    """
    defstruct name: nil, primary_key: true
    @type t :: %__MODULE__{name: atom, primary_key: boolean}
  end

  defmodule Reference do
    @moduledoc """
    Defines a reference struct used in migrations.
    """
    defstruct table: nil, column: :id, type: :integer
    @type t :: %__MODULE__{table: atom, column: atom, type: atom}
  end

  alias Ecto.Migration.Runner

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      import Ecto.Migration
      def __migration__, do: true
    end
  end

  @doc """
  Creates a table.

  ## Examples

      create table(:posts) do
        add :title, :string, default: "Untitled"
        add :body,  :text
      end

  """
  defmacro create(object, do: block) do
    quote(location: :keep) do
      table = unquote(object)
      Runner.start_command({:create, table})

      if table.primary_key do
        add(:id, :serial, primary_key: true)
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
      end

  """
  defmacro alter(object, do: block) do
    quote(location: :keep) do
      Runner.start_command({:alter, unquote(object)})
      unquote(block)
      Runner.end_command
    end
  end

  @doc """
  Creates an index.

  ## Examples

      create index(:posts, [:name])

  """
  def create(%{} = object) do
    Runner.execute {:create, object}
  end

  @doc """
  Drops a table or index.

  ## Examples

      drop index(:posts, [:name])
      drop table(:posts)

  """
  def drop(%{} = object) do
    Runner.execute {:drop, object}
  end

  @doc """
  Returns a table struct that can be given on create, alter, etc.

  ## Examples

      create table(:products) do
        add :name, :string
        add :price, :decimal
      end

      drop table(:products)

  ## Options

    * `:primary_key` - when false, does not generate primary key for table

  """
  def table(name, opts \\ []) when is_atom(name) do
    struct(%Table{name: name}, opts)
  end

  @doc """
  Returns an index struct that can be used on `create`, `drop`, etc.

  Indexes are non-unique by default.

  ## Examples

      # Without a name, index defaults to products_category_id_sku_index
      create index(:products, [:category_id, :sku], unique: true)

      # Name can be given explicitly though
      drop index(:products, [:category_id, :sku], name: :my_special_name)
  """
  def index(table, columns, opts \\ []) when is_atom(table) and is_list(columns) do
    index = struct(%Index{table: table, columns: columns}, opts)
    %{index | name: index.name || default_index_name(index)}
  end

  defp default_index_name(index) do
    [index.table, index.columns, "index"]
    |> List.flatten
    |> Enum.join("_")
    |> String.to_atom
  end

  @doc """
  Executes arbitrary SQL.

  ## Examples

      execute "UPDATE posts SET published_at = NULL"

  """
  def execute(command) when is_binary(command) do
    Runner.execute command
  end

  @doc """
  Adds a column when creating or altering a table.

  ## Examples

      create table(:posts) do
        add :title, :string, default: "Untitled"
      end

      alter table(:posts) do
        add :summary, :text
      end

  ## Options

    * `:default` - the column's default value.
    * `:primary_key` - when true, marks this field as the primary key
    * `:null` - when `false`, the column does not allow null values.
    * `:size` - the size of the type (for example the numbers of characters). Default is no size.
    * `:precision` - the precision for a numberic type. Default is no precision.
    * `:scale` - the scale of a numberic type. Default is 0 scale.

  """
  def add(column, type \\ :string, opts \\ []) when is_atom(column) do
    Runner.subcommand {:add, column, type, opts}
  end

  @doc """
  Modifies a column when altering a table.

  ## Examples

      alter table(:posts) do
        modify :title, :text
      end

  ## Options

  Accepts the same options as `add/3`.
  """
  def modify(column, type, opts \\ []) when is_atom(column) do
    Runner.subcommand {:modify, column, type, opts}
  end

  @doc """
  Removes a column when altering a table.

  ## Examples

      alter table(:posts) do
        remove :title
      end

  """
  def remove(column) when is_atom(column) do
    Runner.subcommand {:remove, column}
  end

  @doc """
  Adds a foreign key.

  ## Examples

      create table(:product) do
        add :category_id, references(:category)
      end

  ## Options

    * `:column` - The foreign key column, default is `:id`
    * `:type`   - The foreign key type, default is `:integer`

  """
  def references(table, opts \\ []) when is_atom(table) do
    struct(%Reference{table: table}, opts)
  end

  @doc """
  Checks if a table or index exists.

  ## Examples

      exists? table(:products)

  """
  def exists?(%{} = object) do
    Runner.exists?(object)
  end
end
