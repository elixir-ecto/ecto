defmodule Ecto.Repo do
  @moduledoc """
  Defines a repository.

  A repository maps to an underlying data store, controlled by the
  adapter. For example, Ecto ships with a Postgres adapter that
  stores data into a PostgreSQL database.

  When used, the repository expects the `:otp_app` as option.
  The `:otp_app` should point to an OTP application that has
  the repository configuration. For example, the repository:

      defmodule Repo do
        use Ecto.Repo,
          otp_app: :my_app,
          adapter: Ecto.Adapters.Postgres
      end

  Could be configured with:

      config :my_app, Repo,
        database: "ecto_simple",
        username: "postgres",
        password: "postgres",
        hostname: "localhost"

  Most of the configuration that goes into the `config` is specific
  to the adapter, so check `Ecto.Adapters.Postgres` documentation
  for more information. However, some configuration is shared across
  all adapters, they are:

    * `:name`- The name of the Repo supervisor process

    * `:priv` - the directory where to keep repository data, like
      migrations, schema and more. Defaults to "priv/YOUR_REPO".
      It must always point to a subdirectory inside the priv directory.

    * `:url` - an URL that specifies storage information. Read below
      for more information

    * `:log` - the log level used when logging the query with Elixir's
      Logger. If false, disables logging for that repository.
      Defaults to `:debug`.

    * `:telemetry_prefix` - we recommend adapters to publish events
      using the `Telemetry` library. By default, the telemetry prefix
      is based on the module name, so if your module is called
      `MyApp.Repo`, the prefix will be `[:my_app, :repo]`. See the
      "Telemetry Events" section to see which events we recommend
      adapters to publish

  ## URLs

  Repositories by default support URLs. For example, the configuration
  above could be rewritten to:

      config :my_app, Repo,
        url: "ecto://postgres:postgres@localhost/ecto_simple"

  The schema can be of any value. The path represents the database name
  while options are simply merged in.

  URL can include query parameters to override shared and adapter-specific
  options `ssl`, `timeout`, `pool_size`:

      config :my_app, Repo,
        url: "ecto://postgres:postgres@localhost/ecto_simple?ssl=true&pool_size=10"

  In case the URL needs to be dynamically configured, for example by
  reading a system environment variable, such can be done via the
  `c:init/2` repository callback:

      def init(_type, config) do
        {:ok, Keyword.put(config, :url, System.get_env("DATABASE_URL"))}
      end

  ## Shared options

  Almost all of the repository operations below accept the following
  options:

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:log` - When false, does not log the query
    * `:telemetry_event` - The telemetry event name to dispatch the event under

  Such cases will be explicitly documented as well as any extra option.

  ## Telemetry events

  We recommend adapters to publish certain `Telemetry` events listed below.
  Those events will use the `:telemetry_prefix` outlined above which defaults
  to `[:my_app, :repo]`.

  For instance, to receive all query events published by a repository called
  `MyApp.Repo`, one would define a module:

      defmodule MyApp.Telemetry do
        def handle_event([:my_app, :repo, :query], time, metadata, config) do
          IO.inspect binding()
        end
      end

  and then attach this module to each event on your Application start callback:

      :telemetry.attach("my-app-handler", [:my_app, :repo, :query], &MyApp.Telemetry.handle_event/4, %{})

  Below we list all events developers should expect. All examples below consider
  a repository named `MyApp.Repo`:

    * `[:my_app, :repo, :query]` - should be invoked on every query send
      to the adapter, including queries that are related to the transaction
      management. The measurement will be the time necessary to run the query
      including queue and encoding time. The metadata is a map where we recommend
      developers to pass at least the same keys as found in the `Ecto.LogEntry`
      struct

  """

  @type t :: module

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Ecto.Repo

      {otp_app, adapter, behaviours} = Ecto.Repo.Supervisor.compile_config(__MODULE__, opts)
      @otp_app otp_app
      @adapter adapter
      @before_compile adapter

      def config do
        {:ok, config} = Ecto.Repo.Supervisor.runtime_config(:runtime, __MODULE__, @otp_app, [])
        config
      end

      def __adapter__ do
        @adapter
      end

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }
      end

      def start_link(opts \\ []) do
        Ecto.Repo.Supervisor.start_link(__MODULE__, @otp_app, @adapter, opts)
      end

      def stop(timeout \\ 5000) do
        Supervisor.stop(__MODULE__, :normal, timeout)
      end

      def load(schema_or_types, data) do
        Ecto.Repo.Schema.load(@adapter, schema_or_types, data)
      end

      def checkout(fun, opts \\ []) when is_function(fun) do
        {adapter, meta} = Ecto.Repo.Registry.lookup(__MODULE__)
        adapter.checkout(meta, opts, fun)
      end

      ## Transactions

      if Ecto.Adapter.Transaction in behaviours do
        def transaction(fun_or_multi, opts \\ []) do
          Ecto.Repo.Transaction.transaction(__MODULE__, fun_or_multi, opts)
        end

        def in_transaction? do
          Ecto.Repo.Transaction.in_transaction?(__MODULE__)
        end

        @spec rollback(term) :: no_return
        def rollback(value) do
          Ecto.Repo.Transaction.rollback(__MODULE__, value)
        end
      end

      ## Schemas

      if Ecto.Adapter.Schema in behaviours do
        def insert(struct, opts \\ []) do
          Ecto.Repo.Schema.insert(__MODULE__, struct, opts)
        end

        def update(struct, opts \\ []) do
          Ecto.Repo.Schema.update(__MODULE__, struct, opts)
        end

        def insert_or_update(changeset, opts \\ []) do
          Ecto.Repo.Schema.insert_or_update(__MODULE__, changeset, opts)
        end

        def delete(struct, opts \\ []) do
          Ecto.Repo.Schema.delete(__MODULE__, struct, opts)
        end

        def insert!(struct, opts \\ []) do
          Ecto.Repo.Schema.insert!(__MODULE__, struct, opts)
        end

        def update!(struct, opts \\ []) do
          Ecto.Repo.Schema.update!(__MODULE__, struct, opts)
        end

        def insert_or_update!(changeset, opts \\ []) do
          Ecto.Repo.Schema.insert_or_update!(__MODULE__, changeset, opts)
        end

        def delete!(struct, opts \\ []) do
          Ecto.Repo.Schema.delete!(__MODULE__, struct, opts)
        end

        def insert_all(schema_or_source, entries, opts \\ []) do
          Ecto.Repo.Schema.insert_all(__MODULE__, schema_or_source, entries, opts)
        end
      end

      ## Queryable

      if Ecto.Adapter.Queryable in behaviours do
        def update_all(queryable, updates, opts \\ []) do
          Ecto.Repo.Queryable.update_all(__MODULE__, queryable, updates, opts)
        end

        def delete_all(queryable, opts \\ []) do
          Ecto.Repo.Queryable.delete_all(__MODULE__, queryable, opts)
        end

        def all(queryable, opts \\ []) do
          Ecto.Repo.Queryable.all(__MODULE__, queryable, opts)
        end

        def stream(queryable, opts \\ []) do
          Ecto.Repo.Queryable.stream(__MODULE__, queryable, opts)
        end

        def get(queryable, id, opts \\ []) do
          Ecto.Repo.Queryable.get(__MODULE__, queryable, id, opts)
        end

        def get!(queryable, id, opts \\ []) do
          Ecto.Repo.Queryable.get!(__MODULE__, queryable, id, opts)
        end

        def get_by(queryable, clauses, opts \\ []) do
          Ecto.Repo.Queryable.get_by(__MODULE__, queryable, clauses, opts)
        end

        def get_by!(queryable, clauses, opts \\ []) do
          Ecto.Repo.Queryable.get_by!(__MODULE__, queryable, clauses, opts)
        end

        def one(queryable, opts \\ []) do
          Ecto.Repo.Queryable.one(__MODULE__, queryable, opts)
        end

        def one!(queryable, opts \\ []) do
          Ecto.Repo.Queryable.one!(__MODULE__, queryable, opts)
        end

        def aggregate(queryable, aggregate, field, opts \\ [])
            when aggregate in [:count, :avg, :max, :min, :sum] and is_atom(field) do
          Ecto.Repo.Queryable.aggregate(__MODULE__, queryable, aggregate, field, opts)
        end

        def exists?(queryable, opts \\ []) do
          Ecto.Repo.Queryable.exists?(__MODULE__, queryable, opts)
        end

        def preload(struct_or_structs_or_nil, preloads, opts \\ []) do
          Ecto.Repo.Preloader.preload(struct_or_structs_or_nil, __MODULE__, preloads, opts)
        end
      end
    end
  end

  ## User callbacks

  @optional_callbacks init: 2

  @doc """
  A callback executed when the repo starts or when configuration is read.

  The first argument is the context the callback is being invoked. If it
  is called because the Repo supervisor is starting, it will be `:supervisor`.
  It will be `:runtime` if it is called for reading configuration without
  actually starting a process.

  The second argument is the repository configuration as stored in the
  application environment. It must return `{:ok, keyword}` with the updated
  list of configuration or `:ignore` (only in the `:supervisor` case).
  """
  @callback init(:supervisor | :runtime, config :: Keyword.t()) :: {:ok, Keyword.t()} | :ignore

  ## Ecto.Adapter

  @doc """
  Returns the adapter tied to the repository.
  """
  @callback __adapter__ :: Ecto.Adapter.t()

  @doc """
  Returns the adapter configuration stored in the `:otp_app` environment.

  If the `c:init/2` callback is implemented in the repository,
  it will be invoked with the first argument set to `:runtime`.
  """
  @callback config() :: Keyword.t()

  @doc """
  Starts any connection pooling or supervision and return `{:ok, pid}`
  or just `:ok` if nothing needs to be done.

  Returns `{:error, {:already_started, pid}}` if the repo is already
  started or `{:error, term}` in case anything else goes wrong.

  ## Options

  See the configuration in the moduledoc for options shared between adapters,
  for adapter-specific configuration see the adapter's documentation.
  """
  @callback start_link(opts :: Keyword.t()) ::
              {:ok, pid}
              | {:error, {:already_started, pid}}
              | {:error, term}

  @doc """
  Shuts down the repository.
  """
  @callback stop(timeout) :: :ok

  @doc """
  Checks out a connection for the duration of the function.

  It returns the result of the function. This is useful when
  you need to perform multiple operations against the repository
  in a row and you want to avoid checking out the connection
  multiple times.

  `checkout/2` and `transaction/2` can be combined and nested
  multiple times. If `checkout/2` is called inside the function
  of another `checkout/2` call, the function is simply executed,
  without checking out a new connection.

  ## Options

  See the "Shared options" section at the module documentation.
  """
  @callback checkout((() -> result), opts :: Keyword.t()) :: result when result: var

  @doc """
  Loads `data` into a struct or a map.

  The first argument can be a a schema module, or a
  map (of types) and determines the return value:
  a struct or a map, respectively.

  The second argument `data` specifies fields and values that are to be loaded.
  It can be a map, a keyword list, or a `{fields, values}` tuple.
  Fields can be atoms or strings.

  Fields that are not present in the schema (or `types` map) are ignored.
  If any of the values has invalid type, an error is raised.

  ## Examples

      iex> MyRepo.load(User, %{name: "Alice", age: 25})
      %User{name: "Alice", age: 25}

      iex> MyRepo.load(User, [name: "Alice", age: 25])
      %User{name: "Alice", age: 25}

  `data` can also take form of `{fields, values}`:

      iex> MyRepo.load(User, {[:name, :age], ["Alice", 25]})
      %User{name: "Alice", age: 25, ...}

  The first argument can also be a `types` map:

      iex> types = %{name: :string, age: :integer}
      iex> MyRepo.load(types, %{name: "Alice", age: 25})
      %{name: "Alice", age: 25}

  This function is especially useful when parsing raw query results:

      iex> result = Ecto.Adapters.SQL.query!(MyRepo, "SELECT * FROM users", [])
      iex> Enum.map(result.rows, &MyRepo.load(User, {result.columns, &1}))
      [%User{...}, ...]

  """
  @callback load(
              module_or_map :: module | map(),
              data :: map() | Keyword.t() | {list, list}
            ) :: Ecto.Schema.t() | map()

  ## Ecto.Adapter.Queryable

  @optional_callbacks get: 3, get!: 3, get_by: 3, get_by!: 3, aggregate: 4, exists?: 2,
                      one: 2, one!: 2, preload: 3, all: 2, stream: 2, update_all: 3, delete_all: 2

  @doc """
  Fetches a single struct from the data store where the primary key matches the
  given id.

  Returns `nil` if no result was found. If the struct in the queryable
  has no or more than one primary key, it will raise an argument error.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      MyRepo.get(Post, 42)

  """
  @callback get(queryable :: Ecto.Queryable.t(), id :: term, opts :: Keyword.t()) ::
              Ecto.Schema.t() | nil

  @doc """
  Similar to `c:get/3` but raises `Ecto.NoResultsError` if no record was found.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      MyRepo.get!(Post, 42)

  """
  @callback get!(queryable :: Ecto.Queryable.t(), id :: term, opts :: Keyword.t()) ::
              Ecto.Schema.t() | nil

  @doc """
  Fetches a single result from the query.

  Returns `nil` if no result was found. Raises if more than one entry.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      MyRepo.get_by(Post, title: "My post")

  """
  @callback get_by(
              queryable :: Ecto.Queryable.t(),
              clauses :: Keyword.t() | map,
              opts :: Keyword.t()
            ) :: Ecto.Schema.t() | nil

  @doc """
  Similar to `get_by/3` but raises `Ecto.NoResultsError` if no record was found.

  Raises if more than one entry.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      MyRepo.get_by!(Post, title: "My post")

  """
  @callback get_by!(
              queryable :: Ecto.Queryable.t(),
              clauses :: Keyword.t() | map,
              opts :: Keyword.t()
            ) :: Ecto.Schema.t() | nil

  @doc """
  Calculate the given `aggregate` over the given `field`.

  If the query has a limit, offset or distinct set, it will be
  automatically wrapped in a subquery in order to return the
  proper result.

  Any preload or select in the query will be ignored in favor of
  the column being aggregated.

  The aggregation will fail if any `group_by` field is set.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Examples

      # Returns the number of visits per blog post
      Repo.aggregate(Post, :count, :visits)

      # Returns the average number of visits for the top 10
      query = from Post, limit: 10
      Repo.aggregate(query, :avg, :visits)
  """
  @callback aggregate(
              queryable :: Ecto.Queryable.t(),
              aggregate :: :avg | :count | :max | :min | :sum,
              field :: atom,
              opts :: Keyword.t()
            ) :: term | nil

  @doc """
  Checks if there exists an entry that matches the given query.

  Returns a boolean.

  ## Options

  See the "Shared options" section at the module documentation.
  """
  @callback exists?(queryable :: Ecto.Queryable.t(), opts :: Keyword.t()) :: boolean()

  @doc """
  Fetches a single result from the query.

  Returns `nil` if no result was found. Raises if more than one entry.

  ## Options

  See the "Shared options" section at the module documentation.
  """
  @callback one(queryable :: Ecto.Queryable.t(), opts :: Keyword.t()) ::
              Ecto.Schema.t() | nil

  @doc """
  Similar to `c:one/2` but raises `Ecto.NoResultsError` if no record was found.

  Raises if more than one entry.

  ## Options

  See the "Shared options" section at the module documentation.
  """
  @callback one!(queryable :: Ecto.Queryable.t(), opts :: Keyword.t()) ::
              Ecto.Schema.t()

  @doc """
  Preloads all associations on the given struct or structs.

  This is similar to `Ecto.Query.preload/3` except it allows
  you to preload structs after they have been fetched from the
  database.

  In case the association was already loaded, preload won't attempt
  to reload it.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:force` - By default, Ecto won't preload associations that
      are already loaded. By setting this option to true, any existing
      association will be discarded and reloaded.
    * `:in_parallel` - If the preloads must be done in parallel. It can
      only be performed when we have more than one preload and the
      repository is not in a transaction. Defaults to `true`.
    * `:prefix` - the prefix to fetch preloads from. By default, queries
      will use the same prefix as the one in the given collection. This
      option allows the prefix to be changed.

  ## Examples

      # Use a single atom to preload an association
      posts = Repo.preload posts, :comments

      # Use a list of atoms to preload multiple associations
      posts = Repo.preload posts, [:comments, :authors]

      # Use a keyword list to preload nested associations as well
      posts = Repo.preload posts, [comments: [:replies, :likes], authors: []]

      # Use a keyword list to customize how associations are queried
      posts = Repo.preload posts, [comments: from(c in Comment, order_by: c.published_at)]

      # Use a two-element tuple for a custom query and nested association definition
      query = from c in Comment, order_by: c.published_at
      posts = Repo.preload posts, [comments: {query, [:replies, :likes]}]

  The query given to preload may also preload its own associations.
  """
  @callback preload(structs_or_struct_or_nil, preloads :: term, opts :: Keyword.t()) ::
              structs_or_struct_or_nil
            when structs_or_struct_or_nil: [Ecto.Schema.t()] | Ecto.Schema.t() | nil

  @doc """
  Fetches all entries from the data store matching the given query.

  May raise `Ecto.QueryError` if query validation fails.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the query.

  See the "Shared options" section at the module documentation.

  ## Example

      # Fetch all post titles
      query = from p in Post,
           select: p.title
      MyRepo.all(query)
  """
  @callback all(queryable :: Ecto.Queryable.t(), opts :: Keyword.t()) :: [Ecto.Schema.t()]

  @doc """
  Returns a lazy enumerable that emits all entries from the data store
  matching the given query.

  SQL adapters, such as Postgres and MySQL, can only enumerate a stream
  inside a transaction.

  May raise `Ecto.QueryError` if query validation fails.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the query

    * `:max_rows` - The number of rows to load from the database as we stream.
      It is supported at least by Postgres and MySQL and defaults to 500.

  See the "Shared options" section at the module documentation.

  ## Example

      # Fetch all post titles
      query = from p in Post,
           select: p.title
      stream = MyRepo.stream(query)
      MyRepo.transaction(fn() ->
        Enum.to_list(stream)
      end)
  """
  @callback stream(queryable :: Ecto.Queryable.t(), opts :: Keyword.t()) :: Enum.t()

  @doc """
  Updates all entries matching the given query with the given values.

  It returns a tuple containing the number of entries and any returned
  result as second element. The second element is `nil` by default
  unless a `select` is supplied in the update query. Note, however,
  not all databases support returning data from UPDATEs.

  Keep in mind this `update_all` will not update autogenerated
  fields like the `updated_at` columns.

  See `Ecto.Query.update/3` for update operations that can be
  performed on fields.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the query.

  See the "Shared options" section at the module documentation for
  remaining options.

  ## Examples

      MyRepo.update_all(Post, set: [title: "New title"])

      MyRepo.update_all(Post, inc: [visits: 1])

      from(p in Post, where: p.id < 10, select: p.visits)
      |> MyRepo.update_all(set: [title: "New title"])

      from(p in Post, where: p.id < 10, update: [set: [title: "New title"]])
      |> MyRepo.update_all([])

      from(p in Post, where: p.id < 10, update: [set: [title: ^new_title]])
      |> MyRepo.update_all([])

      from(p in Post, where: p.id < 10, update: [set: [title: fragment("upper(?)", ^new_title)]])
      |> MyRepo.update_all([])

  """
  @callback update_all(
              queryable :: Ecto.Queryable.t(),
              updates :: Keyword.t(),
              opts :: Keyword.t()
            ) :: {integer, nil | [term]}

  @doc """
  Deletes all entries matching the given query.

  It returns a tuple containing the number of entries and any returned
  result as second element. The second element is `nil` by default
  unless a `select` is supplied in the update query. Note, however,
  not all databases support returning data from DELETEs.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the query.

  See the "Shared options" section at the module documentation for
  remaining options.

  ## Examples

      MyRepo.delete_all(Post)

      from(p in Post, where: p.id < 10) |> MyRepo.delete_all
  """
  @callback delete_all(queryable :: Ecto.Queryable.t(), opts :: Keyword.t()) ::
              {integer, nil | [term]}

  ## Ecto.Adapter.Schema

  @optional_callbacks insert_all: 3, insert: 2, insert!: 2, update: 2, update!: 2,
                      delete: 2, delete!: 2, insert_or_update: 2, insert_or_update!: 2

  @doc """
  Inserts all entries into the repository.

  It expects a schema module (`MyApp.User`) or a source (`"users"`) or
  both (`{"users", MyApp.User}`) as the first argument. The second
  argument is a list of entries to be inserted, either as keyword
  lists or as maps. The keys of the entries are the field names as
  atoms and the value should be the respective value for the field
  type or, optionally, an `Ecto.Query` that returns a single entry
  with a single value.

  It returns a tuple containing the number of entries
  and any returned result as second element. If the database
  does not support RETURNING in INSERT statements or no
  return result was selected, the second element will be `nil`.

  When a schema module is given, the entries given will be properly dumped
  before being sent to the database. If the schema contains an
  autogenerated ID field, it will be handled either at the adapter
  or the storage layer. However any other autogenerated value, like
  timestamps, won't be autogenerated when using `c:insert_all/3`.
  This is by design as this function aims to be a more direct way
  to insert data into the database without the conveniences of
  `c:insert/2`. This is also consistent with `c:update_all/3` that
  does not handle timestamps as well.

  It is also not possible to use `insert_all` to insert across multiple
  tables, therefore associations are not supported.

  If a source is given, without a schema module, the given fields are passed
  as is to the adapter.

  ## Options

    * `:returning` - selects which fields to return. When `true`,
      returns all fields in the given schema. May be a list of
      fields, where a struct is still returned but only with the
      given fields. Or `false`, where nothing is returned (the default).
      This option is not supported by all databases.
    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL).
    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `:replace_all`, `:replace_all_except_primary_key`, `{:replace, fields}`,
      a keyword list of update instructions, `{:replace, fields}` or an `Ecto.Query`
      query for updates. See the "Upserts" section for more information.
    * `:conflict_target` - A list of column names to verify for conflicts.
      It is expected those columns to have unique indexes on them that may conflict.
      If none is specified, the conflict target is left up to the database.
      It may also be `{:constraint, constraint_name_as_atom}` in databases
      that support the "ON CONSTRAINT" expression, such as PostgreSQL, or
      `{:unsafe_fragment, binary_fragment}` to pass any expression to the
      database without any sanitization, such as
      `ON CONFLICT (coalesce(firstname, ""), coalesce(lastname, ""))`.

  See the "Shared options" section at the module documentation for
  remaining options.

  ## Examples

      MyRepo.insert_all(Post, [[title: "My first post"], [title: "My second post"]])
      MyRepo.insert_all(Post, [%{title: "My first post"}, %{title: "My second post"}])

  ## Upserts

  `c:insert_all/3` provides upserts (update or inserts) via the `:on_conflict`
  option. The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting primary key or unique index
    * `:nothing` - ignores the error in case of conflicts
    * `:replace_all` - replace all values on the existing row by the new entry,
      including values not sent explicitly by Ecto, such as database defaults.
      This option requires a schema
    * `:replace_all_except_primary_key` - same as above except primary keys are
      not replaced. This option requires a schema
    * `{:replace, fields}` - replace only specific columns. This option requires
      conflict_target
    * a keyword list of update instructions - such as the one given to
      `c:update_all/3`, for example: `[set: [title: "new title"]]`
    * an `Ecto.Query` that will act as an `UPDATE` statement, such as the
      one given to `c:update_all/3`

  Upserts map to "ON CONFLICT" on databases like Postgres and "ON DUPLICATE KEY"
  on databases such as MySQL.

  ## Return values

  By default, both Postgres and MySQL return the amount of entries
  inserted on `c:insert_all/3`. However, when the `:on_conflict` option
  is specified, Postgres will only return a row if it was affected
  while MySQL returns at least the number of entries attempted.

  For example, if `:on_conflict` is set to `:nothing`, Postgres will
  return 0 if no new entry was added while MySQL will still return
  the amount of entries attempted to be inserted, even if no entry
  was added. Even worse, if `:on_conflict` is query, MySQL will return
  the number of attempted entries plus the number of entries modified
  by the UPDATE query.
  """
  @callback insert_all(
              schema_or_source :: binary | {binary, module} | module,
              entries :: [map | [{atom, term | Ecto.Query.t}]],
              opts :: Keyword.t()
            ) :: {integer, nil | [term]}

  @doc """
  Inserts a struct defined via `Ecto.Schema` or a changeset.

  In case a struct is given, the struct is converted into a changeset
  with all non-nil fields as part of the changeset.

  In case a changeset is given, the changes in the changeset are
  merged with the struct fields, and all of them are sent to the
  database.

  It returns `{:ok, struct}` if the struct has been successfully
  inserted or `{:error, changeset}` if there was a validation
  or a known constraint error.

  ## Options

    * `:returning` - selects which fields to return. When `true`, returns
      all fields in the given struct. May be a list of fields, where a
      struct is still returned but only with the given fields. In any case,
      it will include fields with `read_after_writes` set to true.
      Not all databases support this option.
    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the struct.
    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `:replace_all`, `:replace_all_except_primary_key`, `{:replace, fields}`,
      a keyword list of update instructions or an `Ecto.Query` query for updates.
      See the "Upserts" section for more information.
    * `:conflict_target` - A list of column names to verify for conflicts.
      It is expected those columns to have unique indexes on them that may conflict.
      If none is specified, the conflict target is left up to the database.
      May also be `{:constraint, constraint_name_as_atom}` in databases
      that support the "ON CONSTRAINT" expression, such as PostgreSQL.
    * `:stale_error_field` - The field where stale errors will be added in
      the returning changeset. This option can be used to avoid raising
      `Ecto.StaleEntryError`.
    * `:stale_error_message` - The message to add to the configured
      `:stale_error_field` when stale errors happen, defaults to "is stale".

  See the "Shared options" section at the module documentation.

  ## Examples

  A typical example is calling `MyRepo.insert/1` with a struct
  and acting on the return value:

      case MyRepo.insert %Post{title: "Ecto is great"} do
        {:ok, struct}       -> # Inserted with success
        {:error, changeset} -> # Something went wrong
      end

  ## Upserts

  `c:insert/2` provides upserts (update or inserts) via the `:on_conflict`
  option. The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting primary key or unique index
    * `:nothing` - ignores the error in case of conflicts
    * `:replace_all` - replace all values on the existing row with the values
      in the schema/changeset, including autogenerated fields such as `inserted_at`
      and `updated_at`
    * `:replace_all_except_primary_key` - same as above except primary keys are
      not replaced
    * `{:replace, fields}` - replace only specific columns. This option requires
      conflict_target
    * a keyword list of update instructions - such as the one given to
      `c:update_all/3`, for example: `[set: [title: "new title"]]`
    * an `Ecto.Query` that will act as an `UPDATE` statement, such as the
      one given to `c:update_all/3`. If the struct cannot be found, `Ecto.StaleEntryError`
      will be raised.

  Upserts map to "ON CONFLICT" on databases like Postgres and "ON DUPLICATE KEY"
  on databases such as MySQL.

  As an example, imagine `:title` is marked as a unique column in
  the database:

      {:ok, inserted} = MyRepo.insert(%Post{title: "this is unique"})

  Now we can insert with the same title but do nothing on conflicts:

      {:ok, ignored} = MyRepo.insert(%Post{title: "this is unique"}, on_conflict: :nothing)
      assert ignored.id == nil

  Because we used `on_conflict: :nothing`, instead of getting an error,
  we got `{:ok, struct}`. However the returned struct does not reflect
  the data in the database. One possible mechanism to detect if an
  insert or nothing happened in case of `on_conflict: :nothing` is by
  checking the `id` field. `id` will be nil if the field is autogenerated
  by the database and no insert happened.

  For actual upserts, where an insert or update may happen, the situation
  is slightly more complex, as the database does not actually inform us
  if an insert or update happened. Let's insert a post with the same title
  but use a query to update the body column in case of conflicts:

      # In Postgres (it requires the conflict target for updates):
      on_conflict = [set: [body: "updated"]]
      {:ok, updated} = MyRepo.insert(%Post{title: "this is unique"},
                                     on_conflict: on_conflict, conflict_target: :title)

      # In MySQL (conflict target is not supported):
      on_conflict = [set: [title: "updated"]]
      {:ok, updated} = MyRepo.insert(%Post{id: inserted.id, title: "updated"},
                                     on_conflict: on_conflict)

  In the examples above, even though it returned `:ok`, we do not know
  if we inserted new data or if we updated only the `:on_conflict` fields.
  In case an update happened, the data in the struct most likely does
  not match the data in the database. For example, autogenerated fields
  such as `inserted_at` will point to now rather than the time the
  struct was actually inserted.

  If you need to guarantee the data in the returned struct mirrors the
  database, you have three options:

    * Use `on_conflict: :replace_all`, although that will replace all
      fields in the database with the ones in the struct/changeset,
      including autogenerated fields such as `insert_at` and `updated_at`:

          MyRepo.insert(%Post{title: "this is unique"},
                        on_conflict: :replace_all, conflict_target: :title)

    * Specify `read_after_writes: true` in your schema for choosing
      fields that are read from the database after every operation.
      Or pass `returning: true` to `insert` to read all fields back:

          MyRepo.insert(%Post{title: "this is unique"}, returning: true,
                        on_conflict: on_conflict, conflict_target: :title)

    * Alternatively, read the data again from the database in a separate
      query. This option requires the primary key to be generated by the
      database:

          {:ok, updated} = MyRepo.insert(%Post{title: "this is unique"}, on_conflict: on_conflict)
          Repo.get(Post, updated.id)

  Because of the inability to know if the struct is up to date or not,
  using associations with the `:on_conflict` option is not recommended.
  For instance, Ecto may even trigger constraint violations when associations
  are used with `on_conflict: :nothing`, as no ID will be available in
  the case the record already exists, and it is not possible for Ecto to
  detect such cases reliably.
  """
  @callback insert(
              struct_or_changeset :: Ecto.Schema.t() | Ecto.Changeset.t(),
              opts :: Keyword.t()
            ) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Updates a changeset using its primary key.

  A changeset is required as it is the only mechanism for
  tracking dirty changes. Only the fields present in the `changes` part
  of the changeset are sent to the database. Any other, in-memory
  changes done to the schema are ignored.

  If the struct has no primary key, `Ecto.NoPrimaryKeyFieldError`
  will be raised.

  If the struct cannot be found, `Ecto.StaleEntryError` will be raised.

  It returns `{:ok, struct}` if the struct has been successfully
  updated or `{:error, changeset}` if there was a validation
  or a known constraint error.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:force` - By default, if there are no changes in the changeset,
      `c:update/2` is a no-op. By setting this option to true, update
      callbacks will always be executed, even if there are no changes
      (including timestamps).
    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the struct.
    * `:stale_error_field` - The field where stale errors will be added in
      the returning changeset. This option can be used to avoid raising
      `Ecto.StaleEntryError`.
    * `:stale_error_message` - The message to add to the configured
      `:stale_error_field` when stale errors happen, defaults to "is stale".

  ## Example

      post = MyRepo.get!(Post, 42)
      post = Ecto.Changeset.change post, title: "New title"
      case MyRepo.update post do
        {:ok, struct}       -> # Updated with success
        {:error, changeset} -> # Something went wrong
      end
  """
  @callback update(changeset :: Ecto.Changeset.t(), opts :: Keyword.t()) ::
              {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Inserts or updates a changeset depending on whether the struct is persisted
  or not.

  The distinction whether to insert or update will be made on the
  `Ecto.Schema.Metadata` field `:state`. The `:state` is automatically set by
  Ecto when loading or building a schema.

  Please note that for this to work, you will have to load existing structs from
  the database. So even if the struct exists, this won't work:

      struct = %Post{id: "existing_id", ...}
      MyRepo.insert_or_update changeset
      # => {:error, changeset} # id already exists

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the struct.

  See the "Shared options" section at the module documentation.

  ## Example

      result =
        case MyRepo.get(Post, id) do
          nil  -> %Post{id: id} # Post not found, we build one
          post -> post          # Post exists, let's use it
        end
        |> Post.changeset(changes)
        |> MyRepo.insert_or_update

      case result do
        {:ok, struct}       -> # Inserted or updated with success
        {:error, changeset} -> # Something went wrong
      end
  """
  @callback insert_or_update(changeset :: Ecto.Changeset.t(), opts :: Keyword.t()) ::
              {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Deletes a struct using its primary key.

  If the struct has no primary key, `Ecto.NoPrimaryKeyFieldError`
  will be raised. If the struct has been removed from db prior to
  call, `Ecto.StaleEntryError` will be raised.

  It returns `{:ok, struct}` if the struct has been successfully
  deleted or `{:error, changeset}` if there was a validation
  or a known constraint error.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the struct.
    * `:stale_error_field` - The field where stale errors will be added in
      the returning changeset. This option can be used to avoid raising
      `Ecto.StaleEntryError`.
    * `:stale_error_message` - The message to add to the configured
      `:stale_error_field` when stale errors happen, defaults to "is stale".

  See the "Shared options" section at the module documentation.

  ## Example

      post = MyRepo.get!(Post, 42)
      case MyRepo.delete post do
        {:ok, struct}       -> # Deleted with success
        {:error, changeset} -> # Something went wrong
      end

  """
  @callback delete(
              struct_or_changeset :: Ecto.Schema.t() | Ecto.Changeset.t(),
              opts :: Keyword.t()
            ) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Same as `c:insert/2` but returns the struct or raises if the changeset is invalid.
  """
  @callback insert!(
              struct_or_changeset :: Ecto.Schema.t() | Ecto.Changeset.t(),
              opts :: Keyword.t()
            ) :: Ecto.Schema.t()

  @doc """
  Same as `c:update/2` but returns the struct or raises if the changeset is invalid.
  """
  @callback update!(changeset :: Ecto.Changeset.t(), opts :: Keyword.t()) ::
              Ecto.Schema.t()

  @doc """
  Same as `c:insert_or_update/2` but returns the struct or raises if the changeset
  is invalid.
  """
  @callback insert_or_update!(changeset :: Ecto.Changeset.t(), opts :: Keyword.t()) ::
              Ecto.Schema.t()

  @doc """
  Same as `c:delete/2` but returns the struct or raises if the changeset is invalid.
  """
  @callback delete!(
              struct_or_changeset :: Ecto.Schema.t() | Ecto.Changeset.t(),
              opts :: Keyword.t()
            ) :: Ecto.Schema.t()

  ## Ecto.Adapter.Transaction

  @optional_callbacks transaction: 2, in_transaction?: 0, rollback: 1

  @doc """
  Runs the given function or `Ecto.Multi` inside a transaction.

  ## Use with function

  If an unhandled error occurs the transaction will be rolled back
  and the error will bubble up from the transaction function.
  If no error occurred the transaction will be committed when the
  function returns. A transaction can be explicitly rolled back
  by calling `c:rollback/1`, this will immediately leave the function
  and return the value given to `rollback` as `{:error, value}`.

  A successful transaction returns the value returned by the function
  wrapped in a tuple as `{:ok, value}`.

  If `c:transaction/2` is called inside another transaction, the function
  is simply executed, without wrapping the new transaction call in any
  way. If there is an error in the inner transaction and the error is
  rescued, or the inner transaction is rolled back, the whole outer
  transaction is marked as tainted, guaranteeing nothing will be committed.

  ## Use with Ecto.Multi

  Besides functions transaction can be used with an Ecto.Multi struct.
  Transaction will be started, all operations applied and in case of
  success committed returning `{:ok, changes}`. In case of any errors
  the transaction will be rolled back and
  `{:error, failed_operation, failed_value, changes_so_far}` will be
  returned.

  You can read more about using transactions with `Ecto.Multi` as well as
  see some examples in the `Ecto.Multi` documentation.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Examples

      import Ecto.Changeset, only: [change: 2]

      MyRepo.transaction(fn ->
        MyRepo.update!(change(alice, balance: alice.balance - 10))
        MyRepo.update!(change(bob, balance: bob.balance + 10))
      end)

      # Roll back a transaction explicitly
      MyRepo.transaction(fn ->
        p = MyRepo.insert!(%Post{})
        if not Editor.post_allowed?(p) do
          MyRepo.rollback(:posting_not_allowed)
        end
      end)

      # With Ecto.Multi
      Ecto.Multi.new
      |> Ecto.Multi.insert(:post, %Post{})
      |> MyRepo.transaction

  """
  @callback transaction(fun_or_multi :: fun | Ecto.Multi.t(), opts :: Keyword.t()) ::
              {:ok, any}
              | {:error, any}
              | {:error, Ecto.Multi.name(), any, %{Ecto.Multi.name() => any}}

  @doc """
  Returns true if the current process is inside a transaction.

  If you are using the `Ecto.Adapters.SQL.Sandbox` in tests, note that even
  though each test is inside a transaction, `in_transaction?/0` will only
  return true inside transactions explicitly created with `transaction/2`. This
  is done so the test environment mimics dev and prod.

  If you are trying to debug transaction-related code while using
  `Ecto.Adapters.SQL.Sandbox`, it may be more helpful to configure the database
  to log all statements and consult those logs.

  ## Examples

      MyRepo.in_transaction?
      #=> false

      MyRepo.transaction(fn ->
        MyRepo.in_transaction? #=> true
      end)

  """
  @callback in_transaction?() :: boolean

  @doc """
  Rolls back the current transaction.

  The transaction will return the value given as `{:error, value}`.
  """
  @callback rollback(value :: any) :: no_return
end
