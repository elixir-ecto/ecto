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
          create table("weather") do
            add :city,    :string, size: 40
            add :temp_lo, :integer
            add :temp_hi, :integer
            add :prcp,    :float

            timestamps()
          end
        end

        def down do
          drop table("weather")
        end
      end

  Note that migrations have `up/0` and `down/0` instructions, where
  `up/0` applies changes to the database and `down/0` rolls back
  changes, returning the database schema to a previous state.

  Ecto creates a table (see the `:migration_source` configuration option)
  in the database in order to keep track of migrations and will add
  an entry to this table for each migration you define. Ecto also
  locks the table when adding/removing entries, guaranteeing two
  different servers cannot run the same migration at the same time.

  Ecto provides some mix tasks to help developers work with migrations:

    * `mix ecto.gen.migration add_weather_table` - generates a
      migration that the user can fill in with particular commands
    * `mix ecto.migrate` - migrates a repository
    * `mix ecto.rollback` - rolls back a particular migration

  Run `mix help COMMAND` for more information on a particular command.

  ## Change

  `change/0` is an abstraction that wraps both `up/0` and `down/0` for
  automatically-reversible migrations. For example, the migration above
  can be written as:

      defmodule MyRepo.Migrations.AddWeatherTable do
        use Ecto.Migration

        def change do
          create table("weather") do
            add :city,    :string, size: 40
            add :temp_lo, :integer
            add :temp_hi, :integer
            add :prcp,    :float

            timestamps()
          end
        end
      end

  However, note that not all commands are reversible. Trying to rollback
  a non-reversible command will raise an `Ecto.MigrationError`.

  A notable command in this regard is `execute/2`, which accepts a pair
  of plain SQL strings, the first to run on forward migrations (`up/0`)
  and the second when rolling back (`down/0`).

  If `up/0` and `down/0` are implemented in a migration, they take precedence, and
  `change/0` isn't invoked.

  ## Field Types

  The Ecto primitive types are mapped to the appropriate database
  type by the various database adapters. For example, `:string` is converted to
  `:varchar`, `:binary` to `:bits` or `:blob`, and so on.

  Similarly, you can pass any field type supported by your database
  as long as it maps to an Ecto type. For instance, you can use `:text`,
  `:varchar`, or `:char` in your migrations as `add :field_name, :text`.
  In your Ecto schema, they will all map to the same `:string` type.

  Remember, atoms can contain arbitrary characters by enclosing in
  double quotes the characters following the colon. So, if you want to use a
  field type with database-specific options, you can pass atoms containing
  these options like `:"int unsigned"`, `:"time without time zone"`, etc.

  ## Prefixes

  Migrations support specifying a table prefix or index prefix which will
  target either a schema (if using PostgreSQL) or a different database (if using
  MySQL). If no prefix is provided, the default schema or database is used.

  Any reference declared in the table migration refers by default to the table
  with the same declared prefix. The prefix is specified in the table options:

      def up do
        create table("weather", prefix: "north_america") do
          add :city,    :string, size: 40
          add :temp_lo, :integer
          add :temp_hi, :integer
          add :prcp,    :float
          add :group_id, references(:groups)

          timestamps()
        end

        create index("weather", [:city], prefix: "north_america")
      end

  Note: if using MySQL with a prefixed table, you must use the same prefix
  for the references since cross-database references are not supported.

  When using a prefixed table with either MySQL or PostgreSQL, you must use the
  same prefix for the index field to ensure that you index the prefix-qualified
  table.

  ## Transactions

  For PostgreSQL, Ecto always runs migrations inside a transaction, but that's not
  always desired: for example, you cannot create/drop indexes concurrently inside
  a transaction (see the [PostgreSQL docs](http://www.postgresql.org/docs/9.2/static/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY)).

  Migrations can be forced to run outside a transaction by setting the
  `@disable_ddl_transaction` module attribute to `true`:

      defmodule MyRepo.Migrations.CreateIndexes do
        use Ecto.Migration
        @disable_ddl_transaction true

        def change do
          create index("posts", [:slug], concurrently: true)
        end
      end

  Since running migrations outside a transaction can be dangerous, consider
  performing very few operations in such migrations.

  See the `index/3` function for more information on creating/dropping indexes
  concurrently.

  ## Comments

  Migrations where you create or alter a table support specifying table
  and column comments. The same can be done when creating constraints
  and indexes. Not all databases support this feature.

      def up do
        create index("posts", [:name], comment: "Index Comment")
        create constraint("products", "price_must_be_positive", check: "price > 0", comment: "Index Comment")
        create table("weather", prefix: "north_america", comment: "Table Comment") do
          add :city, :string, size: 40, comment: "Column Comment"
          timestamps()
        end
      end

  ## Repo configuration

  The following migration configuration options are available for a given repository:

    * `:migration_source` - Version numbers of migrations will be saved in a
      table named `schema_migrations` by default. You can configure the name of
      the table via:

          config :app, App.Repo, migration_source: "my_migrations"

    * `:migration_primary_key` - By default, Ecto uses the `:id` column with type
      `:bigserial`, but you can configure it via:

          config :app, App.Repo, migration_primary_key: [name: :uuid, type: :binary_id]

    * `:migration_timestamps` - By default, Ecto uses the `:naive_datetime` type, but
      you can configure it via:

          config :app, App.Repo, migration_timestamps: [type: :utc_datetime]

    * `:migration_lock` - By default, Ecto will lock the migration table to handle
      concurrent migrators using `FOR UPDATE`, but you can configure it via:

          config :app, App.Repo, migration_lock: nil

    * `:migration_default_prefix` - Ecto defaults to `nil` for the database prefix for
      migrations, but you can configure it via:

          config :app, App.Repo, migration_default_prefix: "my_prefix"

  """

  defmodule Index do
    @moduledoc """
    Used internally by adapters.

    To define an index in a migration, see `Ecto.Migration.index/3`.
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
      table: String.t,
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

    To define a table in a migration, see `Ecto.Migration.table/2`.
    """
    defstruct name: nil, prefix: nil, comment: nil, primary_key: true, engine: nil, options: nil
    @type t :: %__MODULE__{name: String.t, prefix: atom | nil, comment: String.t | nil, primary_key: boolean,
                           engine: atom, options: String.t}
  end

  defmodule Reference do
    @moduledoc """
    Used internally by adapters.

    To define a reference in a migration, see `Ecto.Migration.references/2`.
    """
    defstruct name: nil, table: nil, column: :id, type: :bigserial, on_delete: :nothing, on_update: :nothing
    @type t :: %__MODULE__{table: String.t, column: atom, type: atom, on_delete: atom, on_update: atom}
  end

  defmodule Constraint do
    @moduledoc """
    Used internally by adapters.

    To define a constraint in a migration, see `Ecto.Migration.constraint/3`.
    """
    defstruct name: nil, table: nil, check: nil, exclude: nil, prefix: nil, comment: nil
    @type t :: %__MODULE__{name: atom, table: String.t, prefix: atom | nil,
                           check: String.t | nil, exclude: String.t | nil, comment: String.t | nil}
  end

  defmodule Command do
    @moduledoc """
    Used internally by adapters.

    This represents the up and down legs of a reversible raw command
    that is usually defined with `Ecto.Migration.execute/1`.

    To define a reversible command in a migration, see `Ecto.Migration.execute/2`.
    """
    defstruct up: nil, down: nil
    @type t :: %__MODULE__{up: String.t, down: String.t}
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

  By default, the table will also include an `:id` primary key field that
  has a type of `:bigserial`. Check the `table/2` docs for more information.

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

  Works just like `create/2` but does not raise an error when the table
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
        opts = Runner.repo_config(:migration_primary_key, [])
        opts = Keyword.put(opts, :primary_key, true)

        {name, opts} = Keyword.pop(opts, :name, :id)
        {type, opts} = Keyword.pop(opts, :type, :bigserial)

        add(name, type, opts)
      end

      unquote(block)
      Runner.end_command
      table
    end
  end

  @doc """
  Alters a table.

  ## Examples

      alter table("posts") do
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

  When reversing (in a `change/0` running backwards), indexes are only dropped
  if they exist, and no errors are raised. To enforce dropping an index, use
  `drop/1`.

  ## Examples

      create index("posts", [:name])
      create table("version")
      create constraint("products", "price_must_be_positive", check: "price > 0")

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

      create_if_not_exists index("posts", [:name])

      create_if_not_exists table("version")

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
        [{:add, :id, :bigserial, primary_key: true}]
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

      drop index("posts", [:name])
      drop table("posts")
      drop constraint("products", "price_must_be_positive")

  """
  def drop(%{} = index_or_table_or_constraint) do
    Runner.execute {:drop, __prefix__(index_or_table_or_constraint)}
    index_or_table_or_constraint
  end

  @doc """
  Drops a table or index if it exists.

  Does not raise an error if the specified table or index does not exist.

  ## Examples

      drop_if_exists index("posts", [:name])
      drop_if_exists table("posts")

  """
  def drop_if_exists(%{} = index_or_table) do
    Runner.execute {:drop_if_exists, __prefix__(index_or_table)}
    index_or_table
  end

  @doc """
  Returns a table struct that can be given to `create/2`, `alter/2`, `drop/1`,
  etc.

  ## Examples

      create table("products") do
        add :name, :string
        add :price, :decimal
      end

      drop table("products")

      create table("products", primary_key: false) do
        add :name, :string
        add :price, :decimal
      end

  ## Options

    * `:primary_key` - when `false`, a primary key field is not generated on table
      creation.
    * `:engine` - customizes the table storage for supported databases. For MySQL,
      the default is InnoDB.
    * `:prefix` - the prefix for the table.
    * `:options` - provide custom options that will be appended after the generated
      statement. For example, "WITH", "INHERITS", or "ON COMMIT" clauses.

  """
  def table(name, opts \\ [])

  def table(name, opts) when is_atom(name) do
    table(Atom.to_string(name), opts)
  end

  def table(name, opts) when is_binary(name) and is_list(opts) do
    struct(%Table{name: name}, opts)
  end

  @doc ~S"""
  Returns an index struct that can be given to `create/1`, `drop/1`, etc.

  Expects the table name as the first argument and the index field(s) as
  the second. The fields can be atoms, representing columns, or strings,
  representing expressions that are sent as-is to the database.

  ## Options

    * `:name` - the name of the index. Defaults to "#{table}_#{column}_index".
    * `:unique` - indicates whether the index should be unique. Defaults to
      `false`.
    * `:concurrently` - indicates whether the index should be created/dropped
      concurrently.
    * `:using` - configures the index type.
    * `:prefix` - specify an optional prefix for the index.
    * `:where` - specify conditions for a partial index.

  ## Adding/dropping indexes concurrently

  PostgreSQL supports adding/dropping indexes concurrently (see the
  [docs](http://www.postgresql.org/docs/9.4/static/sql-createindex.html)).
  In order to take advantage of this, the `:concurrently` option needs to be set
  to `true` when the index is created/dropped.

  **Note**: in order for the `:concurrently` option to work, the migration must
  not be run inside a transaction. See the `Ecto.Migration` docs for more
  information on running migrations outside of a transaction.

  ## Index types

  When creating an index, the index type can be specified with the `:using`
  option. The `:using` option can be an atom or a string, and its value is
  passed to the generated `USING` clause as-is.

  For example, PostgreSQL supports several index types like B-tree (the
  default), Hash, GIN, and GiST. More information on index types can be found
  in the [PostgreSQL docs]
  (http://www.postgresql.org/docs/9.4/static/indexes-types.html).

  ## Partial indexes

  Databases like PostgreSQL and MSSQL support partial indexes.

  A partial index is an index built over a subset of a table. The subset
  is defined by a conditional expression using the `:where` option.
  The `:where` option can be an atom or a string; its value is passed
  to the generated `WHERE` clause as-is.

  More information on partial indexes can be found in the [PostgreSQL
  docs](http://www.postgresql.org/docs/9.4/static/indexes-partial.html).

  ## Examples

      # With no name provided, the name of the below index defaults to
      # products_category_id_sku_index
      create index("products", [:category_id, :sku], unique: true)

      # The name can also be set explicitly
      drop index("products", [:category_id, :sku], name: :my_special_name)

      # Indexes can be added concurrently
      create index("products", [:category_id, :sku], concurrently: true)

      # The index type can be specified
      create index("products", [:name], using: :hash)

      # Partial indexes are created by specifying a :where option
      create index("products", [:user_id], where: "price = 0", name: :free_products_index)

  Indexes also support custom expressions. Some databases may require the
  index expression to be written between parentheses:

      # Create an index on a custom expression
      create index("products", ["(lower(name))"], name: :products_lower_name_index)

      # Create a tsvector GIN index on PostgreSQL
      create index("products", ["(to_tsvector('english', name))"],
                   name: :products_name_vector, using: "GIN")
  """
  def index(table, columns, opts \\ [])

  def index(table, columns, opts) when is_atom(table) do
    index(Atom.to_string(table), columns, opts)
  end

  def index(table, column, opts) when is_binary(table) and is_atom(column) do
    index(table, [column], opts)
  end

  def index(table, columns, opts) when is_binary(table) and is_list(columns) and is_list(opts) do
    validate_index_opts!(opts)
    index = struct(%Index{table: table, columns: columns}, opts)
    %{index | name: index.name || default_index_name(index)}
  end

  @doc """
  Shortcut for creating a unique index.

  See `index/3` for more information.
  """
  def unique_index(table, columns, opts \\ [])

  def unique_index(table, columns, opts) when is_list(opts) do
    index(table, columns, [unique: true] ++ opts)
  end

  defp default_index_name(index) do
    [index.table, index.columns, "index"]
    |> List.flatten
    |> Enum.map(&to_string(&1))
    |> Enum.map(&String.replace(&1, ~r"[^\w_]", "_"))
    |> Enum.map(&String.replace_trailing(&1, "_", ""))
    |> Enum.join("_")
    |> String.to_atom
  end

  @doc """
  Executes arbitrary SQL or a keyword command.

  Reversible commands can be defined by calling `execute/2`.

  ## Examples

      execute "CREATE EXTENSION postgres_fdw"

      execute create: "posts", capped: true, size: 1024

  """
  def execute(command) when is_binary(command) or is_list(command) do
    Runner.execute command
  end

  @doc """
  Executes reversible SQL commands.

  This is useful for database-specific functionality that does not
  warrant special support in Ecto, for example, creating and dropping
  a PostgreSQL extension. The `execute/2` form avoids having to define
  separate `up/0` and `down/0` blocks that each contain an `execute/1`
  expression.

  ## Examples

      execute "CREATE EXTENSION postgres_fdw", "DROP EXTENSION postgres_fdw"

  """
  def execute(up, down) when (is_binary(up) or is_list(up)) and
                             (is_binary(down) or is_list(down)) do
    Runner.execute %Command{up: up, down: down}
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
  that are normalized by the database adapter. For example,
  `:string` is converted to `:varchar`, `:binary` to `:bits` or `:blob`,
  and so on.

  However, the column type is not always the same as the type used in your
  schema. For example, a schema that has a `:string` field can be supported by
  columns of type `:char`, `:varchar`, `:text`, and others. For this reason,
  this function also accepts `:text` and other type annotations that are native
  to the database. These are passed to the database as-is.

  To sum up, the column type may be either an Ecto primitive type,
  which is normalized in cases where the database does not understand it,
  such as `:string` or `:binary`, or a database type which is passed as-is.
  Custom Ecto types like `Ecto.UUID` are not supported because
  they are application-level concerns and may not always map to the database.

  ## Examples

      create table("posts") do
        add :title, :string, default: "Untitled"
      end

      alter table("posts") do
        add :summary, :text # Database type
        add :object,  :map  # Elixir type which is handled by the database
      end

  ## Options

    * `:primary_key` - when `true`, marks this field as the primary key.
    * `:default` - the column's default value. It can be a string, number, empty
      list, list of strings, list of numbers, or a fragment generated by
      `fragment/1`.
    * `:null` - when `false`, the column does not allow null values.
    * `:size` - the size of the type (for example, the number of characters).
      The default is no size, except for `:string`, which defaults to `255`.
    * `:precision` - the precision for a numeric type. Required when `:scale` is
      specified.
    * `:scale` - the scale of a numeric type. Defaults to `0`.

  """
  def add(column, type, opts \\ [])

  def add(column, :datetime, _opts) when is_atom(column) do
    raise ArgumentError, "the :datetime type in migrations is not supported, " <>
                         "please use :utc_datetime or :naive_datetime instead"
  end

  def add(column, type, opts) when is_atom(column) and is_list(opts) do
    if opts[:scale] && !opts[:precision] do
      raise ArgumentError, "column #{Atom.to_string(column)} is missing precision option"
    end

    validate_type!(type)
    Runner.subcommand {:add, column, type, opts}
  end

  @doc """
  Renames a table.

  ## Examples

      rename table("posts"), to: table("new_posts")
  """
  def rename(%Table{} = table_current, to: %Table{} = table_new) do
    Runner.execute {:rename, __prefix__(table_current), __prefix__(table_new)}
    table_new
  end

  @doc """
  Renames a column outside of the `alter` statement.

  ## Examples

      rename table("posts"), :title, to: :summary
  """
  def rename(%Table{} = table, current_column, to: new_column) when is_atom(current_column) and is_atom(new_column) do
    Runner.execute {:rename, __prefix__(table), current_column, new_column}
    table
  end

  @doc """
  Generates a fragment to be used as a default value.

  ## Examples

      create table("posts") do
        add :inserted_at, :naive_datetime, default: fragment("now()")
      end
  """
  def fragment(expr) when is_binary(expr) do
    {:fragment, expr}
  end

  @doc """
  Adds `:inserted_at` and `:updated_at` timestamp columns.

  Those columns are of `:naive_datetime` type and by default cannot be null. A
  list of `opts` can be given to customize the generated fields.

  ## Options

    * `:inserted_at` - the name of the column for storing insertion times.
      Setting it to `false` disables the column.
    * `:updated_at` - the name of the column for storing last-updated-at times.
      Setting it to `false` disables the column.
    * `:type` - the type of the `:inserted_at` and `:updated_at` columns.
      Defaults to `:naive_datetime`.

  """
  def timestamps(opts \\ []) when is_list(opts) do
    opts = Keyword.merge(Runner.repo_config(:migration_timestamps, []), opts)
    opts = Keyword.put_new(opts, :null, false)

    {type, opts} = Keyword.pop(opts, :type, :naive_datetime)
    {inserted_at, opts} = Keyword.pop(opts, :inserted_at, :inserted_at)
    {updated_at, opts} = Keyword.pop(opts, :updated_at, :updated_at)

    if inserted_at != false, do: add(inserted_at, type, opts)
    if updated_at != false, do: add(updated_at, type, opts)
  end

  @doc """
  Modifies the type of a column when altering a table.

  This command is not reversible unless the `:from` option is provided.
  If the `:from` value is a `%Reference{}`, the adapter will try to drop
  the corresponding foreign key constraints before modifying the type.

  See `add/3` for more information on supported types.

  ## Examples

      alter table("posts") do
        modify :title, :text
      end

  ## Options

    * `:null` - determines whether the column accepts null values.
    * `:default` - changes the default value of the column.
    * `:from` - specifies the current type of the column.
    * `:size` - specifies the size of the type (for example, the number of characters).
      The default is no size.
    * `:precision` - the precision for a numeric type. Required when `:scale` is
      specified.
    * `:scale` - the scale of a numeric type. Defaults to `0`.
  """
  def modify(column, type, opts \\ [])

  def modify(column, :datetime, _opts) when is_atom(column) do
    raise ArgumentError, "the :datetime type in migrations is not supported, " <>
                         "please use :utc_datetime or :naive_datetime instead"
  end

  def modify(column, type, opts) when is_atom(column) and is_list(opts) do
    if opts[:scale] && !opts[:precision] do
      raise ArgumentError, "column #{Atom.to_string(column)} is missing precision option"
    end

    Runner.subcommand {:modify, column, type, opts}
  end

  @doc """
  Removes a column when altering a table.

  This command is not reversible as Ecto does not know what type it should add
  the column back as. See `remove/3` as a reversible alternative.

  ## Examples

      alter table("posts") do
        remove :title
      end

  """
  def remove(column) when is_atom(column) do
    Runner.subcommand {:remove, column}
  end

  @doc """
  Removes a column in a reversible way when altering a table.

  `type` and `opts` are exactly the same as in `add/3`, and
  they are only used when the command is reversed.

  ## Examples

      alter table("posts") do
        remove :title, :string, default: ""
      end

  """
  def remove(column, type, opts \\ []) when is_atom(column) do
    Runner.subcommand {:remove, column, type, opts}
  end

  @doc ~S"""
  Defines a foreign key.

  ## Examples

      create table("products") do
        add :group_id, references("groups")
      end

  ## Options

    * `:name` - The name of the underlying reference, which defaults to
      "#{table}_#{column}_fkey".
    * `:column` - The foreign key column name, which defaults to `:id`.
    * `:type` - The foreign key type, which defaults to `:bigserial`.
    * `:on_delete` - What to do if the referenced entry is deleted. May be
      `:nothing` (default), `:delete_all`, `:nilify_all`, or `:restrict`.
    * `:on_update` - What to do if the referenced entry is updated. May be
      `:nothing` (default), `:update_all`, `:nilify_all`, or `:restrict`.

  """
  def references(table, opts \\ [])

  def references(table, opts) when is_atom(table) do
    references(Atom.to_string(table), opts)
  end

  def references(table, opts) when is_binary(table) and is_list(opts) do
    repo_opts = Keyword.take(Runner.repo_config(:migration_primary_key, []), [:type])
    opts = Keyword.merge(repo_opts, opts)
    reference = struct(%Reference{table: table}, opts)

    unless reference.on_delete in [:nothing, :delete_all, :nilify_all, :restrict] do
      raise ArgumentError, "unknown :on_delete value: #{inspect reference.on_delete}"
    end

    unless reference.on_update in [:nothing, :update_all, :nilify_all, :restrict] do
      raise ArgumentError, "unknown :on_update value: #{inspect reference.on_update}"
    end

    reference
  end

  @doc ~S"""
  Defines a constraint (either a check constraint or an exclusion constraint)
  to be evaluated by the database when a row is inserted or updated.

  ## Examples

      create constraint("users", :price_must_be_positive, check: "price > 0")
      create constraint("size_ranges", :no_overlap, exclude: ~s|gist (int4range("from", "to", '[]') WITH &&)|)
      drop   constraint("products", "price_must_be_positive")

  ## Options

    * `:check` - A check constraint expression. Required when creating a check constraint.
    * `:exclude` - An exclusion constraint expression. Required when creating an exclusion constraint.
    * `:prefix` - The prefix for the table.

  """
  def constraint(table, name, opts \\ [])

  def constraint(table, name, opts) when is_atom(table) do
    constraint(Atom.to_string(table), name, opts)
  end

  def constraint(table, name, opts) when is_binary(table) and is_list(opts) do
    struct(%Constraint{table: table, name: name}, opts)
  end

  @doc """
  Executes queue migration commands.

  Reverses the order in which commands are executed when doing a rollback
  on a `change/0` function and resets the commands queue.
  """
  def flush do
    Runner.flush
  end

  # Validation helpers
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

  defp validate_index_opts!(opts) when is_list(opts) do
    case Keyword.get_values(opts, :where) do
      [_, _ | _] ->
        raise ArgumentError,
              "only one `where` keyword is supported when declaring a partial index. " <>
                "To specify multiple conditions, write a single WHERE clause using AND between them"

      _ ->
        :ok
    end
  end

  defp validate_index_opts!(opts), do: opts

  @doc false
  def __prefix__(%{prefix: prefix} = index_or_table) do
    runner_prefix = Runner.prefix()

    cond do
      is_nil(prefix) ->
        prefix = runner_prefix || Runner.repo_config(:migration_default_prefix, nil)
        %{index_or_table | prefix: prefix}
      is_nil(runner_prefix) or runner_prefix == to_string(prefix) ->
        index_or_table
      true ->
        raise Ecto.MigrationError,  message:
          "the :prefix option `#{prefix}` does match the migrator prefix `#{runner_prefix}`"
    end
  end
end
