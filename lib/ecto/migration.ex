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

            timestamps
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

    * `mix ecto.gen.migration add_weather_table` - generates a
      migration that the user can fill in with particular commands
    * `mix ecto.migrate` - migrates a repository
    * `mix ecto.rollback` - rolls back a particular migration

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

            timestamps
          end
        end
      end

  Notice not all commands are reversible though. Trying to rollback
  a non-reversible command will raise an `Ecto.MigrationError`.

  ## Transactions

  By default, Ecto runs all migrations inside a transaction. That's not always
  ideal: for example, PostgreSQL allows to create/drop indexes concurrently but
  only outside of any transaction (see the [PostgreSQL
  docs](http://www.postgresql.org/docs/9.2/static/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY)).

  Migrations can be forced to run outside a transaction by setting the
  `@disable_ddl_transaction` module attribute to `true`:

      defmodule MyRepo.Migrations.CreateIndexes do
        use Ecto.Migration
        @disable_ddl_transaction true

        def change do
          create index(:posts, [:slug], concurrently: true)
        end
      end

  Since running migrations outside a transaction can be dangerous, consider
  performing very few operations in such migrations.

  See the `index/3` function for more information on creating/dropping indexes
  concurrently.

  """

  defmodule Index do
    @moduledoc """
    Defines an index struct used in migrations.
    """
    defstruct table: nil,
              name: nil,
              columns: [],
              unique: false,
              concurrently: false,
              using: nil

    @type t :: %__MODULE__{
      table: atom,
      name: atom,
      columns: [atom | String.t],
      unique: boolean,
      concurrently: boolean,
      using: atom | String.t
    }
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
      @disable_ddl_transaction false
      @before_compile Ecto.Migration
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      def __migration__,
        do: [disable_ddl_transaction: @disable_ddl_transaction]
    end
  end

  @doc """
  Creates a table.

  By default, the table will also include a primary_key of name `:id`
  and type `:serial`. Check `table/2` docs for more information.

  ## Examples

      create table(:posts) do
        add :title, :string, default: "Untitled"
        add :body,  :text

        timestamps
      end

  """
  defmacro create(object, do: block) do
    quote do
      table = %Table{} = unquote(object)
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
    quote do
      table = %Table{} = unquote(object)
      Runner.start_command({:alter, table})
      unquote(block)
      Runner.end_command
    end
  end

  @doc """
  Creates an index.

  When reversing (in `change` running backward) indexes are only dropped if they
  exist and no errors are raised. To enforce dropping an index use `drop/1`.

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

      create table(:products, primary_key: false) do
        add :name, :string
        add :price, :decimal
      end

  ## Options

    * `:primary_key` - when false, does not generate primary key on table creation

  """
  def table(name, opts \\ []) when is_atom(name) do
    struct(%Table{name: name}, opts)
  end

  @doc """
  Returns an index struct that can be used on `create`, `drop`, etc.

  Expects the table name as first argument and the index fields as
  second. The field can be an atom, representing a column, or a
  string representing an expression that is sent as is to the database.

  Indexes are non-unique by default.

  ## Adding/dropping indexes concurrently

  PostgreSQL supports adding/dropping indexes concurrently (see the
  [docs](http://www.postgresql.org/docs/9.4/static/sql-createindex.html)).
  In order to take advantage of this, the `:concurrently` option needs to be set
  to `true` when the index is created/dropped.

  **Note**: in order for the `:concurrently` option to work, the migration must
  not be run inside a transaction. See the `Ecto.Migration` docs for more
  information on running migrations outside of a transaction.

  ## Index types

  PostgreSQL supports several index types like B-tree, Hash or GiST. When
  creating an index, the index type defaults to B-tree, but it can be specified
  with the `:using` option. The `:using` option can be an atom or a string; its
  value is passed to the `USING` clause as is.

  More information on index types can be found in the [PostgreSQL
  docs](http://www.postgresql.org/docs/9.4/static/indexes-types.html).

  ## Examples

      # Without a name, index defaults to products_category_id_sku_index
      create index(:products, [:category_id, :sku], unique: true)

      # Name can be given explicitly though
      drop index(:products, [:category_id, :sku], name: :my_special_name)

      # Indexes can be added concurrently
      create index(:products, [:category_id, :sku], concurrently: true)

      # The index type can be specified
      create index(:products, [:name], using: :hash)

  """
  def index(table, columns, opts \\ []) when is_atom(table) and is_list(columns) do
    index = struct(%Index{table: table, columns: columns}, opts)
    %{index | name: index.name || default_index_name(index)}
  end

  defp default_index_name(index) do
    [index.table, index.columns, "index"]
    |> List.flatten
    |> Enum.join("_")
    |> String.replace(~r"[^\w_]", "_")
    |> String.replace("__", "_")
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

  In order to support database-specific types, in addition to standard
  Ecto types, arbitrary atoms can be used for type names, for example,
  `:json` (if supported by the underlying database).

  ## Examples

      create table(:posts) do
        add :title, :string, default: "Untitled"
      end

      alter table(:posts) do
        add :summary, :text
        add :object,  :json
      end

  ## Options

    * `:primary_key` - when true, marks this field as the primary key
    * `:default` - the column's default value. can be a string, number
      or a fragment generated by `fragment/1`
    * `:null` - when `false`, the column does not allow null values
    * `:size` - the size of the type (for example the numbers of characters). Default is no size
    * `:precision` - the precision for a numberic type. Default is no precision
    * `:scale` - the scale of a numberic type. Default is 0 scale

  """
  def add(column, type \\ :string, opts \\ []) when is_atom(column) do
    Runner.subcommand {:add, column, type, opts}
  end

  @doc """
  Generates a fragment to be used as default value.

  ## Examples

      create table(:posts) do
        add :inserted_at, :datetime, default: fragment("now()")
      end
  """
  def fragment(expr) when is_binary(expr) do
    {:fragment, expr}
  end

  @doc """
  Adds `:inserted_at` and `:updated_at` timestamps columns.

  Those columns are of `:datetime` type and cannot be null.
  """
  def timestamps do
    add(:inserted_at, :datetime, null: false)
    add(:updated_at, :datetime, null: false)
  end

  @doc """
  Modifies the type of column when altering a table.

  ## Examples

      alter table(:posts) do
        modify :title, :text
      end

  ## Options

    * `:size` - the size of the type (for example the numbers of characters). Default is no size.
    * `:precision` - the precision for a numberic type. Default is no precision.
    * `:scale` - the scale of a numberic type. Default is 0 scale.
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
