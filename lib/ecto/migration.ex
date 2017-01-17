defmodule Ecto.Migration do
  @moduledoc """
  Migrations are used to modify your database schema over time.

  This module provides many helpers for migrating the database,
  allowing developers to use Elixir to alter their storage in
  a way that is database independent.

  Here is an example:

      defmodule MyRepo.Migrations.AddWeatherTable do
        use Ecto.Migration

        def up do
          create table(:weather) do
            add :city,    :string, size: 40
            add :temp_lo, :integer
            add :temp_hi, :integer
            add :prcp,    :float

            timestamps()
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

      defmodule MyRepo.Migrations.AddWeatherTable do
        use Ecto.Migration

        def change do
          create table(:weather) do
            add :city,    :string, size: 40
            add :temp_lo, :integer
            add :temp_hi, :integer
            add :prcp,    :float

            timestamps()
          end
        end
      end

  Notice not all commands are reversible though. Trying to rollback
  a non-reversible command will raise an `Ecto.MigrationError`.

  ## Field Types

  The Ecto primitive types are mapped to the appropriate database
  type by the various database adapters. For example, `:string` is converted to
  `:varchar`, `:binary` to `:bits` or `:blob`, and so on.

  Similarly, you can pass any field type supported by your database
  as long as it maps to an Ecto type. For instance, you can use `:text`,
  `:varchar` or `:char` in your migrations as `add :field_name, :text`.
  In your Ecto schema, they will all map to the same `:string` type.

  Remember, atoms can containing arbitrary characters by enclosing in
  double quotes the characters following the colon. So, if you want to use
  field type with your database specific options, you can pass atoms containing
  these options like `:"int unsigned"`, `:"time without time zone"`.

  ## Prefixes

  Migrations support specifying a table prefix or index prefix which will target either a schema
  if using Postgres, or a different database if using MySQL. If no prefix is
  provided, the default schema or database is used.
  Any reference declared in the table migration refers by default to the table with
  the same declared prefix.
  The prefix is specified in the table options:

      def up do
        create table(:weather, prefix: "north_america") do
          add :city,    :string, size: 40
          add :temp_lo, :integer
          add :temp_hi, :integer
          add :prcp,    :float
          add :group_id, references(:groups)

          timestamps()
        end

        create index(:weather, [:city], prefix: "north_america")
      end

  Note: if using MySQL with a prefixed table, you must use the same prefix for the references since
  cross database references are not supported.

  For both MySQL and Postgres with a prefixed table, you must use the same prefix for the index field to ensure
  you index the prefix qualified table.

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

  ## Comments

  Migrations where you create or alter a table support specifying table
  and column comments, the same can be done when creating constraints
  and indexes. At the moment there is support only for Postgres.

      def up do
        create index(:posts, [:name], comment: "Index Comment")
        create constraint(:products, "price_must_be_positive", check: "price > 0", comment: "Index Comment")
        create table(:weather, prefix: "north_america", comment: "Table Comment") do
          add :city, :string, size: 40, comment: "Column Comment"
          timestamps()
        end
      end

  ## Schema Migrations table

  Version numbers of migrations will be saved in `schema_migrations` table.
  But you can configure the table via:

      config :app, App.Repo, migration_source: "my_migrations"

  """

  defmodule Index do
    @moduledoc """
    Used internally by adapters.

    To define an index in a migration, see `Ecto.Migration.index/3`
    """
    defstruct table: nil,
              prefix: nil,
              name: nil,
              columns: [],
              unique: false,
              concurrently: false,
              using: nil,
              where: nil,
              comment: nil,
              options: nil

    @type t :: %__MODULE__{
      table: atom,
      prefix: atom,
      name: atom,
      columns: [atom | String.t],
      unique: boolean,
      concurrently: boolean,
      using: atom | String.t,
      where: atom | String.t,
      comment: String.t | nil,
      options: String.t
    }
  end

  defmodule Table do
    @moduledoc """
    Used internally by adapters.

    To define a table in a migration, see `Ecto.Migration.table/2`
    """
    defstruct name: nil, prefix: nil, comment: nil, primary_key: true, engine: nil, options: nil
    @type t :: %__MODULE__{name: atom, prefix: atom | nil, comment: String.t | nil, primary_key: boolean,
                           engine: atom, options: String.t}
  end

  defmodule Reference do
    @moduledoc """
    Used internally by adapters.

    To define a reference in a migration, see `Ecto.Migration.references/2`
    """
    defstruct name: nil, table: nil, column: :id, type: :serial, on_delete: :nothing, on_update: :nothing
    @type t :: %__MODULE__{table: atom, column: atom, type: atom, on_delete: atom, on_update: atom}
  end

  defmodule Constraint do
    @moduledoc """
    Used internally by adapters.

    To define a constraint in a migration, see `Ecto.Migration.constraint/3`
    """
    defstruct name: nil, table: nil, check: nil, exclude: nil, prefix: nil, comment: nil
    @type t :: %__MODULE__{name: atom, table: atom, prefix: atom | nil,
                           check: String.t | nil, exclude: String.t | nil, comment: String.t | nil}
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

        timestamps()
      end

  """
  defmacro create(object, do: block) do
    expand_create(object, :create, block)
  end

  @doc """
  Creates a table if it does not exist.

  Works just like `create/2` but does not raise an error when table
  already exists.
  """
  defmacro create_if_not_exists(object, do: block) do
    expand_create(object, :create_if_not_exists, block)
  end

  defp expand_create(object, command, block) do
    quote do
      table = %Table{} = unquote(object)
      Runner.start_command({unquote(command), Ecto.Migration.__prefix__(table)})

      if table.primary_key do
        add(:id, :serial, primary_key: true)
      end

      unquote(block)
      Runner.end_command
      table
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
      Runner.start_command({:alter, Ecto.Migration.__prefix__(table)})
      unquote(block)
      Runner.end_command
    end
  end

  @doc """
  Creates one of the following:

    * an index
    * a table with only an `:id` field
    * a constraint

  When reversing (in `change` running backward) indexes are only dropped if they
  exist and no errors are raised. To enforce dropping an index use `drop/1`.

  ## Examples

      create index(:posts, [:name])
      create table(:version)
      create constraint(:products, "price_must_be_positive", check: "price > 0")

  """
  def create(%Index{} = index) do
    Runner.execute {:create, __prefix__(index)}
    index
  end

  def create(%Constraint{} = constraint) do
    Runner.execute {:create, __prefix__(constraint)}
    constraint
  end

  def create(%Table{} = table) do
    do_create table, :create
    table
  end

  @doc """
  Creates an index or a table with only `:id` field if one does not yet exist.

  ## Examples

      create_if_not_exists index(:posts, [:name])

      create_if_not_exists table(:version)

  """
  def create_if_not_exists(%Index{} = index) do
    Runner.execute {:create_if_not_exists, __prefix__(index)}
  end

  def create_if_not_exists(%Table{} = table) do
    do_create table, :create_if_not_exists
  end

  defp do_create(table, command) do
    columns =
      if table.primary_key do
        [{:add, :id, :serial, primary_key: true}]
      else
        []
      end

    Runner.execute {command, __prefix__(table), columns}
  end

  @doc """
  Drops one of the following:

    * an index
    * a table
    * a constraint

  ## Examples

      drop index(:posts, [:name])
      drop table(:posts)
      drop constraint(:products, name: "price_must_be_positive")

  """
  def drop(%{} = index_or_table_or_constraint) do
    Runner.execute {:drop, __prefix__(index_or_table_or_constraint)}
    index_or_table_or_constraint
  end

  @doc """
  Drops a table or index if it exists.

  Does not raise an error if table or index does not exist.

  ## Examples

      drop_if_exists index(:posts, [:name])
      drop_if_exists table(:posts)

  """
  def drop_if_exists(%{} = index_or_table) do
    Runner.execute {:drop_if_exists, __prefix__(index_or_table)}
    index_or_table
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
    * `:engine` - customizes the table storage for supported databases. For MySQL,
      the default is InnoDB
    * `:prefix` - the prefix for the table
    * `:options` - provide custom options that will be appended after generated
      statement, for example "WITH", "INHERITS" or "ON COMMIT" clauses

  """
  def table(name, opts \\ []) when is_atom(name) do
    struct(%Table{name: name}, opts)
  end

  @doc ~S"""
  Returns an index struct that can be used on `create`, `drop`, etc.

  Expects the table name as first argument and the index fields as
  second. The field can be an atom, representing a column, or a
  string representing an expression that is sent as is to the database.

  Indexes are non-unique by default.

  ## Options

    * `:name` - the name of the index. Defaults to "#{table}_#{column}_index"
    * `:unique` - if the column(s) is unique or not
    * `:concurrently` - if the index should be created/dropped concurrently
    * `:using` - configures the index type
    * `:prefix` - prefix for the index
    * `:where` - the conditions for a partial index

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

  ## Partial indexes

  Databases like PostgreSQL and MSSQL supports partial indexes.

  A partial index is an index built over a subset of a table. The subset
  is defined by a conditional expression using the `:where` option.
  The `:where` option can be an atom or a string; its value is passed
  to the `WHERE` clause as is.

  More information on partial indexes can be found in the [PostgreSQL
  docs](http://www.postgresql.org/docs/9.4/static/indexes-partial.html).

  ## Examples

      # Without a name, index defaults to products_category_id_sku_index
      create index(:products, [:category_id, :sku], unique: true)

      # Name can be given explicitly though
      drop index(:products, [:category_id, :sku], name: :my_special_name)

      # Indexes can be added concurrently
      create index(:products, [:category_id, :sku], concurrently: true)

      # The index type can be specified
      create index(:products, [:name], using: :hash)

      # Create an index on custom expressions
      create index(:products, ["lower(name)"], name: :products_lower_name_index)

      # Create a partial index
      create index(:products, [:user_id], where: "price = 0", name: :free_products_index)

  """
  def index(table, columns, opts \\ [])
  def index(table, columns, opts) when is_atom(table) and is_list(columns) do
    index = struct(%Index{table: table, columns: columns}, opts)
    %{index | name: index.name || default_index_name(index)}
  end
  def index(table, column, opts) when is_atom(table) and is_atom(column), do: index(table, [column], opts)

  @doc """
  Shortcut for creating a unique index.

  See `index/3` for more information.
  """
  def unique_index(table, columns, opts \\ [])
  def unique_index(table, columns, opts) when is_atom(table) and is_list(columns) do
    index(table, columns, [unique: true] ++ opts)
  end
  def unique_index(table, column, opts) when is_atom(table) and is_atom(column), do: unique_index(table, [column], opts)

  defp default_index_name(index) do
    [index.table, index.columns, "index"]
    |> List.flatten
    |> Enum.join("_")
    |> String.replace(~r"[^\w_]", "_")
    |> String.replace("__", "_")
    |> String.to_atom
  end

  @doc """
  Executes arbitrary SQL or a keyword command in NoSQL databases.

  ## Examples

      execute "UPDATE posts SET published_at = NULL"

      execute create: "posts", capped: true, size: 1024

  """
  def execute(command) when is_binary(command) or is_list(command) do
    Runner.execute command
  end

  @doc """
  Gets the migrator direction.
  """
  @spec direction :: :up | :down
  def direction do
    Runner.migrator_direction
  end

  @doc """
  Gets the migrator prefix.
  """
  def prefix do
    Runner.prefix
  end

  @doc """
  Adds a column when creating or altering a table.

  This function also accepts Ecto primitive types as column types
  and they are normalized by the database adapter. For example,
  `:string` is converted to `:varchar`, `:binary` to `:bits` or `:blob`,
  and so on.

  However, the column type is not always the same as the type used in your
  schema. For example, a schema that has a `:string` field,
  can be supported by columns of types `:char`, `:varchar`, `:text` and others.
  For this reason, this function also accepts `:text` and other columns,
  which are sent as is to the underlying database.

  To sum up, the column type may be either an Ecto primitive type,
  which is normalized in cases the database does not understand it,
  like `:string` or `:binary`, or a database type which is passed as is.
  Custom Ecto types, like `Ecto.UUID`, are not supported because
  they are application level concern and may not always map to the
  database.

  ## Examples

      create table(:posts) do
        add :title, :string, default: "Untitled"
      end

      alter table(:posts) do
        add :summary, :text # Database type
        add :object,  :map  # Elixir type which is handled by the database
      end

  ## Options

    * `:primary_key` - when true, marks this field as the primary key
    * `:default` - the column's default value. can be a string, number
      or a fragment generated by `fragment/1`
    * `:null` - when `false`, the column does not allow null values
    * `:size` - the size of the type (for example the numbers of characters).
      Default is no size, except for `:string` that defaults to 255.
    * `:precision` - the precision for a numeric type. Default is no precision
    * `:scale` - the scale of a numeric type. Default is 0 scale

  """
  def add(column, type, opts \\ [])

  def add(column, :datetime, opts) when is_atom(column) do
    IO.warn "the :datetime type in migrations is deprecated, " <>
            "please use :utc_datetime or :naive_datetime instead"
    add(column, :naive_datetime, opts)
  end

  def add(column, type, opts) when is_atom(column) do
    validate_type!(type)
    Runner.subcommand {:add, column, type, opts}
  end

  @doc """
  Renames a table.

  ## Examples

      rename table(:posts), to: table(:new_posts)
  """
  def rename(%Table{} = table_current, to: %Table{} = table_new) do
    Runner.execute {:rename, __prefix__(table_current), __prefix__(table_new)}
    table_new
  end

  @doc """
  Renames a column outside of the `alter` statement.

  ## Examples

      rename table(:posts), :title, to: :summary
  """
  def rename(%Table{} = table, current_column, to: new_column) when is_atom(current_column) and is_atom(new_column) do
    Runner.execute {:rename, __prefix__(table), current_column, new_column}
    table
  end

  @doc """
  Generates a fragment to be used as default value.

  ## Examples

      create table(:posts) do
        add :inserted_at, :naive_datetime, default: fragment("now()")
      end
  """
  def fragment(expr) when is_binary(expr) do
    {:fragment, expr}
  end

  @doc """
  Adds `:inserted_at` and `:updated_at` timestamps columns.

  Those columns are of `:naive_datetime` type, and by default
  cannot be null. `opts` can be given to customize the generated
  fields.

  ## Options

    * `:inserted_at` -  the name of the column for insertion times, providing `false` disables column
    * `:updated_at` - the name of the column for update times, providing `false` disables column
    * `:type` - column type, defaults to `:naive_datetime`

  """
  def timestamps(opts \\ []) do
    opts = Keyword.put_new(opts, :null, false)

    {type, opts} = Keyword.pop(opts, :type, :naive_datetime)
    {inserted_at, opts} = Keyword.pop(opts, :inserted_at, :inserted_at)
    {updated_at, opts} = Keyword.pop(opts, :updated_at, :updated_at)

    if inserted_at != false, do: add(inserted_at, type, opts)
    if updated_at != false, do: add(updated_at, type, opts)
  end

  @doc """
  Modifies the type of column when altering a table.

  This command is not reversible as Ecto does not know what
  is the current type to revert it back to.

  See `add/3` for more information on supported types.

  ## Examples

      alter table(:posts) do
        modify :title, :text
      end

  ## Options

    * `:null` - sets to null or not null
    * `:default` - changes the default
    * `:size` - the size of the type (for example the numbers of characters). Default is no size.
    * `:precision` - the precision for a numeric type. Default is no precision.
    * `:scale` - the scale of a numeric type. Default is 0 scale.
  """
  def modify(column, type, opts \\ [])

  def modify(column, :datetime, opts) when is_atom(column) do
    IO.warn "the :datetime type in migrations is deprecated, " <>
            "please use :utc_datetime or :naive_datetime instead"
    modify(column, :naive_datetime, opts)
  end

  def modify(column, type, opts) when is_atom(column) do
    Runner.subcommand {:modify, column, type, opts}
  end

  @doc """
  Removes a column when altering a table.

  This command is not reversible as Ecto does not know what
  is the current type to add the column back as.

  ## Examples

      alter table(:posts) do
        remove :title
      end

  """
  def remove(column) when is_atom(column) do
    Runner.subcommand {:remove, column}
  end

  @doc ~S"""
  Defines a foreign key.

  ## Examples

      create table(:products) do
        add :group_id, references(:groups)
      end

  ## Options

    * `:name` - The name of the underlying reference,
      defaults to "#{table}_#{column}_fkey"
    * `:column` - The foreign key column, default is `:id`
    * `:type`   - The foreign key type, default is `:serial`
    * `:on_delete` - What to perform if the referenced entry
       is deleted. May be `:nothing`, `:delete_all` or
       `:nilify_all`. Defaults to `:nothing`.
    * `:on_update` - What to perform if the referenced entry
       is updated. May be `:nothing`, `:update_all` or
       `:nilify_all`. Defaults to `:nothing`.

  """
  def references(table, opts \\ []) when is_atom(table) do
    reference = struct(%Reference{table: table}, opts)

    unless reference.on_delete in [:nothing, :delete_all, :nilify_all] do
      raise ArgumentError, "unknown :on_delete value: #{inspect reference.on_delete}"
    end

    unless reference.on_update in [:nothing, :update_all, :nilify_all] do
      raise ArgumentError, "unknown :on_update value: #{inspect reference.on_update}"
    end

    reference
  end

  @doc ~S"""
  Defines a constraint (either a check constraint or an exclusion constraint) to be evaluated by the database when a row is inserted or updated.

  ## Examples

      create constraint(:users, :price_must_be_positive, check: "price > 0")
      create constraint(:size_ranges, :no_overlap, exclude: ~s|gist (int4range("from", "to", '[]') WITH &&)|
      drop   constraint(:products, "price_must_be_positive")

  ## Options

    * `:check` - The expression to evaluate on a row. Required when creating.
    * `:name` - The name of the constraint - required.

  """
  def constraint(table, name, opts \\ []) do
    struct(%Constraint{table: table, name: name}, opts)
  end

  @doc """
  Executes queue migration commands.

  Reverses the order commands are executed when doing a rollback
  on a change/0 function and resets commands queue.
  """
  def flush do
    Runner.flush
  end

  defp validate_type!(type) when is_atom(type) do
    case Atom.to_string(type) do
      "Elixir." <> _ ->
        raise ArgumentError,
          "#{inspect type} is not a valid database type, " <>
          "please use an atom like :string, :text and so on"
      _ ->
        :ok
    end
  end

  defp validate_type!({type, subtype}) when is_atom(type) and is_atom(subtype) do
    validate_type!(subtype)
  end

  defp validate_type!({type, subtype}) when is_atom(type) and is_tuple(subtype) do
    for t <- Tuple.to_list(subtype), do: validate_type!(t)
  end

  defp validate_type!(%Reference{} = reference) do
    reference
  end

  @doc false
  def __prefix__(%{prefix: prefix} = index_or_table) do
    runner_prefix = Runner.prefix()

    cond do
      is_nil(prefix) ->
        %{index_or_table | prefix: runner_prefix}
      is_nil(runner_prefix) or runner_prefix == to_string(prefix) ->
        index_or_table
      true ->
        raise Ecto.MigrationError,  message:
          "the :prefix option `#{prefix}` does match the migrator prefix `#{runner_prefix}`"
    end
  end
end
