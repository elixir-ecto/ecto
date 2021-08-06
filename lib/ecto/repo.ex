defmodule Ecto.Repo do
  @moduledoc """
  Defines a repository.

  A repository maps to an underlying data store, controlled by the
  adapter. For example, Ecto ships with a Postgres adapter that
  stores data into a PostgreSQL database.

  When used, the repository expects the `:otp_app` and `:adapter` as
  option. The `:otp_app` should point to an OTP application that has
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
  to the adapter. For this particular example, you can check
  [`Ecto.Adapters.Postgres`](https://hexdocs.pm/ecto_sql/Ecto.Adapters.Postgres.html)
  for more information. In spite of this, the following configuration values
  are shared across all adapters:

    * `:name`- The name of the Repo supervisor process

    * `:priv` - the directory where to keep repository data, like
      migrations, schema and more. Defaults to "priv/YOUR_REPO".
      It must always point to a subdirectory inside the priv directory

    * `:url` - an URL that specifies storage information. Read below
      for more information

    * `:log` - the log level used when logging the query with Elixir's
      Logger. If false, disables logging for that repository.
      Defaults to `:debug`

    * `:pool_size` - the size of the pool used by the connection module.
      Defaults to `10`

    * `:telemetry_prefix` - we recommend adapters to publish events
      using the `Telemetry` library. By default, the telemetry prefix
      is based on the module name, so if your module is called
      `MyApp.Repo`, the prefix will be `[:my_app, :repo]`. See the
      "Telemetry Events" section to see which events we recommend
      adapters to publish. Note that if you have multiple databases, you
      should keep the `:telemetry_prefix` consistent for each repo and
      use the `:repo` property in the event metadata for distinguishing
      between repos.

  ## URLs

  Repositories by default support URLs. For example, the configuration
  above could be rewritten to:

      config :my_app, Repo,
        url: "ecto://postgres:postgres@localhost/ecto_simple"

  The schema can be of any value. The path represents the database name
  while options are simply merged in.

  URL can include query parameters to override shared and adapter-specific
  options, like `ssl`, `timeout` and `pool_size`. The following example
  shows how to pass these configuration values:

      config :my_app, Repo,
        url: "ecto://postgres:postgres@localhost/ecto_simple?ssl=true&pool_size=10"

  In case the URL needs to be dynamically configured, for example by
  reading a system environment variable, such can be done via the
  `c:init/2` repository callback:

      def init(_type, config) do
        {:ok, Keyword.put(config, :url, System.get_env("DATABASE_URL"))}
      end

  ## Shared options

  Almost all of the repository functions outlined in this module accept the following
  options:

    * `:timeout` - The time in milliseconds (as an integer) to wait for the query call to
      finish. `:infinity` will wait indefinitely (default: `15_000`)
    * `:log` - When false, does not log the query
    * `:telemetry_event` - The telemetry event name to dispatch the event under.
      See the next section for more information
    * `:telemetry_options` - Extra options to attach to telemetry event name.
      See the next section for more information

  ## Telemetry events

  There are two types of telemetry events. The ones emitted by Ecto and the
  ones that are adapter specific.

  ### Ecto telemetry events

  The following events are emitted by all Ecto repositories:

    * `[:ecto, :repo, :init]` - it is invoked whenever a repository starts.
      The measurement is a single `system_time` entry in native unit. The
      metadata is the `:repo` and all initialization options under `:opts`.

  ### Adapter-specific events

  We recommend adapters to publish certain `Telemetry` events listed below.
  Those events will use the `:telemetry_prefix` outlined above which defaults
  to `[:my_app, :repo]`.

  For instance, to receive all query events published by a repository called
  `MyApp.Repo`, one would define a module:

      defmodule MyApp.Telemetry do
        def handle_event([:my_app, :repo, :query], measurements, metadata, config) do
          IO.inspect binding()
        end
      end

  Then, in the `Application.start/2` callback, attach the handler to this event using
  a unique handler id:

      :ok = :telemetry.attach("my-app-handler-id", [:my_app, :repo, :query], &MyApp.Telemetry.handle_event/4, %{})

  For details, see [the telemetry documentation](https://hexdocs.pm/telemetry/).

  Below we list all events developers should expect from Ecto. All examples
  below consider a repository named `MyApp.Repo`:

  #### `[:my_app, :repo, :query]`

  This event should be invoked on every query sent to the adapter, including
  queries that are related to the transaction management.

  The `:measurements` map will include the following, all given in the
  `:native` time unit:

    * `:idle_time` - the time the connection spent waiting before being checked out for the query
    * `:queue_time` - the time spent waiting to check out a database connection
    * `:query_time` - the time spent executing the query
    * `:decode_time` - the time spent decoding the data received from the database
    * `:total_time` - the sum of the other measurements

  All measurements are given in the `:native` time unit. You can read more
  about it in the docs for `System.convert_time_unit/3`.

  A telemetry `:metadata` map including the following fields. Each database
  adapter may emit different information here. For Ecto.SQL databases, it
  will look like this:

    * `:type` - the type of the Ecto query. For example, for Ecto.SQL
      databases, it would be `:ecto_sql_query`
    * `:repo` - the Ecto repository
    * `:result` - the query result
    * `:params` - the query parameters
    * `:query` - the query sent to the database as a string
    * `:source` - the source the query was made on (may be nil)
    * `:options` - extra options given to the repo operation under
      `:telemetry_options`

  ## Read-only repositories

  You can mark a repository as read-only by passing the `:read_only`
  flag on `use`:

      use Ecto.Repo, otp_app: ..., adapter: ..., read_only: true

  By passing the `:read_only` option, none of the functions that perform
  write operations, such as `c:insert/2`, `c:insert_all/3`, `c:update_all/3`,
  and friends will be defined.
  """

  @type t :: module

  @doc """
  Returns all running Ecto repositories.

  The list is returned in no particular order. The list
  contains either atoms, for named Ecto repositories, or
  PIDs.
  """
  @spec all_running() :: [atom() | pid()]
  defdelegate all_running(), to: Ecto.Repo.Registry

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Ecto.Repo

      {otp_app, adapter, behaviours} =
        Ecto.Repo.Supervisor.compile_config(__MODULE__, opts)

      @otp_app otp_app
      @adapter adapter
      @default_dynamic_repo opts[:default_dynamic_repo] || __MODULE__
      @read_only opts[:read_only] || false
      @before_compile adapter
      @aggregates [:count, :avg, :max, :min, :sum]

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
        Supervisor.stop(get_dynamic_repo(), :normal, timeout)
      end

      def load(schema_or_types, data) do
        Ecto.Repo.Schema.load(@adapter, schema_or_types, data)
      end

      def checkout(fun, opts \\ []) when is_function(fun) do
        {adapter, meta} = Ecto.Repo.Registry.lookup(get_dynamic_repo())
        adapter.checkout(meta, opts, fun)
      end

      def checked_out? do
        {adapter, meta} = Ecto.Repo.Registry.lookup(get_dynamic_repo())
        adapter.checked_out?(meta)
      end

      @compile {:inline, get_dynamic_repo: 0, with_default_options: 2}

      def get_dynamic_repo() do
        Process.get({__MODULE__, :dynamic_repo}, @default_dynamic_repo)
      end

      def put_dynamic_repo(dynamic) when is_atom(dynamic) or is_pid(dynamic) do
        Process.put({__MODULE__, :dynamic_repo}, dynamic) || @default_dynamic_repo
      end

      def default_options(_operation), do: []
      defoverridable default_options: 1

      defp with_default_options(operation_name, opts) do
        Keyword.merge(default_options(operation_name), opts)
      end

      ## Transactions

      if Ecto.Adapter.Transaction in behaviours do
        def transaction(fun_or_multi, opts \\ []) do
          Ecto.Repo.Transaction.transaction(__MODULE__, get_dynamic_repo(), fun_or_multi, with_default_options(:transaction, opts))
        end

        def in_transaction? do
          Ecto.Repo.Transaction.in_transaction?(get_dynamic_repo())
        end

        @spec rollback(term) :: no_return
        def rollback(value) do
          Ecto.Repo.Transaction.rollback(get_dynamic_repo(), value)
        end
      end

      ## Schemas

      if Ecto.Adapter.Schema in behaviours and not @read_only do
        def insert(struct, opts \\ []) do
          Ecto.Repo.Schema.insert(__MODULE__, get_dynamic_repo(), struct, with_default_options(:insert, opts))
        end

        def update(struct, opts \\ []) do
          Ecto.Repo.Schema.update(__MODULE__, get_dynamic_repo(), struct, with_default_options(:update, opts))
        end

        def insert_or_update(changeset, opts \\ []) do
          Ecto.Repo.Schema.insert_or_update(__MODULE__, get_dynamic_repo(), changeset, with_default_options(:insert_or_update, opts))
        end

        def delete(struct, opts \\ []) do
          Ecto.Repo.Schema.delete(__MODULE__, get_dynamic_repo(), struct, with_default_options(:delete, opts))
        end

        def insert!(struct, opts \\ []) do
          Ecto.Repo.Schema.insert!(__MODULE__, get_dynamic_repo(), struct, with_default_options(:insert, opts))
        end

        def update!(struct, opts \\ []) do
          Ecto.Repo.Schema.update!(__MODULE__, get_dynamic_repo(), struct, with_default_options(:update, opts))
        end

        def insert_or_update!(changeset, opts \\ []) do
          Ecto.Repo.Schema.insert_or_update!(__MODULE__, get_dynamic_repo(), changeset, with_default_options(:insert_or_update, opts))
        end

        def delete!(struct, opts \\ []) do
          Ecto.Repo.Schema.delete!(__MODULE__, get_dynamic_repo(), struct, with_default_options(:delete, opts))
        end

        def insert_all(schema_or_source, entries, opts \\ []) do
          Ecto.Repo.Schema.insert_all(__MODULE__, get_dynamic_repo(), schema_or_source, entries, with_default_options(:insert_all, opts))
        end
      end

      ## Queryable

      if Ecto.Adapter.Queryable in behaviours do
        if not @read_only do
          def update_all(queryable, updates, opts \\ []) do
            Ecto.Repo.Queryable.update_all(get_dynamic_repo(), queryable, updates, with_default_options(:update_all, opts))
          end

          def delete_all(queryable, opts \\ []) do
            Ecto.Repo.Queryable.delete_all(get_dynamic_repo(), queryable, with_default_options(:delete_all, opts))
          end
        end

        def all(queryable, opts \\ []) do
          Ecto.Repo.Queryable.all(get_dynamic_repo(), queryable, with_default_options(:all, opts))
        end

        def stream(queryable, opts \\ []) do
          Ecto.Repo.Queryable.stream(get_dynamic_repo(), queryable, with_default_options(:stream, opts))
        end

        def get(queryable, id, opts \\ []) do
          Ecto.Repo.Queryable.get(get_dynamic_repo(), queryable, id, with_default_options(:all, opts))
        end

        def get!(queryable, id, opts \\ []) do
          Ecto.Repo.Queryable.get!(get_dynamic_repo(), queryable, id, with_default_options(:all, opts))
        end

        def get_by(queryable, clauses, opts \\ []) do
          Ecto.Repo.Queryable.get_by(get_dynamic_repo(), queryable, clauses, with_default_options(:all, opts))
        end

        def get_by!(queryable, clauses, opts \\ []) do
          Ecto.Repo.Queryable.get_by!(get_dynamic_repo(), queryable, clauses, with_default_options(:all, opts))
        end

        def reload(queryable, opts \\ []) do
          Ecto.Repo.Queryable.reload(get_dynamic_repo(), queryable, opts)
        end

        def reload!(queryable, opts \\ []) do
          Ecto.Repo.Queryable.reload!(get_dynamic_repo(), queryable, opts)
        end

        def one(queryable, opts \\ []) do
          Ecto.Repo.Queryable.one(get_dynamic_repo(), queryable, with_default_options(:all, opts))
        end

        def one!(queryable, opts \\ []) do
          Ecto.Repo.Queryable.one!(get_dynamic_repo(), queryable, with_default_options(:all, opts))
        end

        def aggregate(queryable, aggregate, opts \\ [])

        def aggregate(queryable, aggregate, opts)
            when aggregate in [:count] and is_list(opts) do
          Ecto.Repo.Queryable.aggregate(get_dynamic_repo(), queryable, aggregate, with_default_options(:all, opts))
        end

        def aggregate(queryable, aggregate, field)
            when aggregate in @aggregates and is_atom(field) do
          Ecto.Repo.Queryable.aggregate(get_dynamic_repo(), queryable, aggregate, field, with_default_options(:all, []))
        end

        def aggregate(queryable, aggregate, field, opts)
            when aggregate in @aggregates and is_atom(field) and is_list(opts) do
          Ecto.Repo.Queryable.aggregate(get_dynamic_repo(), queryable, aggregate, field, with_default_options(:all, opts))
        end

        def exists?(queryable, opts \\ []) do
          Ecto.Repo.Queryable.exists?(get_dynamic_repo(), queryable, with_default_options(:all, opts))
        end

        def preload(struct_or_structs_or_nil, preloads, opts \\ []) do
          Ecto.Repo.Preloader.preload(struct_or_structs_or_nil, get_dynamic_repo(), preloads, with_default_options(:preload, opts))
        end

        def prepare_query(operation, query, opts), do: {query, opts}
        defoverridable prepare_query: 3
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
  @callback init(context :: :supervisor | :runtime, config :: Keyword.t()) ::
              {:ok, Keyword.t()} | :ignore

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

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.
  """
  @callback checkout((() -> result), opts :: Keyword.t()) :: result when result: var

  @doc """
  Returns true if a connection has been checked out.

  This is true if inside a `c:Ecto.Repo.checkout/2` or
  `c:Ecto.Repo.transaction/2`.

  ## Examples

      MyRepo.checked_out?
      #=> false

      MyRepo.transaction(fn ->
        MyRepo.checked_out? #=> true
      end)

      MyRepo.checkout(fn ->
        MyRepo.checked_out? #=> true
      end)

  """
  @callback checked_out?() :: boolean

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

  To load data from non-database sources, use `Ecto.embedded_load/3`.

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

  @doc """
  Returns the atom name or pid of the current repository.

  See `c:put_dynamic_repo/1` for more information.
  """
  @callback get_dynamic_repo() :: atom() | pid()

  @doc """
  Sets the dynamic repository to be used in further interactions.

  Sometimes you may want a single Ecto repository to talk to
  many different database instances. By default, when you call
  `MyApp.Repo.start_link/1`, it will start a repository with
  name `MyApp.Repo`. But if you want to start multiple repositories,
  you can give each of them a different name:

      MyApp.Repo.start_link(name: :tenant_foo, hostname: "foo.example.com")
      MyApp.Repo.start_link(name: :tenant_bar, hostname: "bar.example.com")

  You can also start repositories without names by explicitly
  setting the name to nil:

      MyApp.Repo.start_link(name: nil, hostname: "temp.example.com")

  However, once the repository is started, you can't directly interact with
  it, since all operations in `MyApp.Repo` are sent by default to the repository
  named `MyApp.Repo`. You can change the default repo at compile time with:

      use Ecto.Repo, default_dynamic_repo: :name_of_repo

  Or you can change it anytime at runtime by calling `put_dynamic_repo/1`:

      MyApp.Repo.put_dynamic_repo(:tenant_foo)

  From this moment on, all future queries done by the current process will
  run on `:tenant_foo`.

  **Note this feature is experimental and may be changed or removed in future
  releases.**
  """
  @callback put_dynamic_repo(name_or_pid :: atom() | pid()) :: atom() | pid()

  ## Ecto.Adapter.Queryable

  @optional_callbacks get: 3, get!: 3, get_by: 3, get_by!: 3, reload: 2, reload!: 2, aggregate: 3,
                      aggregate: 4, exists?: 2, one: 2, one!: 2, preload: 3, all: 2, stream: 2,
                      update_all: 3, delete_all: 2

  @doc """
  Fetches a single struct from the data store where the primary key matches the
  given id.

  Returns `nil` if no result was found. If the struct in the queryable
  has no or more than one primary key, it will raise an argument error.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This will be applied to all `from`
      and `join`s in the query that did not have a prefix previously given
      either via the `:prefix` option on `join`/`from` or via `@schema_prefix`
      in the schema. For more information see the "Query Prefix" section of the
      `Ecto.Query` documentation.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

  ## Example

      MyRepo.get(Post, 42)

      MyRepo.get(Post, 42, prefix: "public")

  """
  @callback get(queryable :: Ecto.Queryable.t(), id :: term, opts :: Keyword.t()) ::
              Ecto.Schema.t() | nil

  @doc """
  Similar to `c:get/3` but raises `Ecto.NoResultsError` if no record was found.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This will be applied to all `from`
      and `join`s in the query that did not have a prefix previously given
      either via the `:prefix` option on `join`/`from` or via `@schema_prefix`
      in the schema. For more information see the "Query Prefix" section of the
      `Ecto.Query` documentation.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

  ## Example

      MyRepo.get!(Post, 42)

      MyRepo.get!(Post, 42, prefix: "public")

  """
  @callback get!(queryable :: Ecto.Queryable.t(), id :: term, opts :: Keyword.t()) ::
              Ecto.Schema.t()

  @doc """
  Fetches a single result from the query.

  Returns `nil` if no result was found. Raises if more than one entry.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This will be applied to all `from`
      and `join`s in the query that did not have a prefix previously given
      either via the `:prefix` option on `join`/`from` or via `@schema_prefix`
      in the schema. For more information see the "Query Prefix" section of the
      `Ecto.Query` documentation.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

  ## Example

      MyRepo.get_by(Post, title: "My post")

      MyRepo.get_by(Post, [title: "My post"], prefix: "public")

  """
  @callback get_by(
              queryable :: Ecto.Queryable.t(),
              clauses :: Keyword.t() | map,
              opts :: Keyword.t()
            ) :: Ecto.Schema.t() | nil

  @doc """
  Similar to `c:get_by/3` but raises `Ecto.NoResultsError` if no record was found.

  Raises if more than one entry.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This will be applied to all `from`
      and `join`s in the query that did not have a prefix previously given
      either via the `:prefix` option on `join`/`from` or via `@schema_prefix`
      in the schema. For more information see the "Query Prefix" section of the
      `Ecto.Query` documentation.


  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

  ## Example

      MyRepo.get_by!(Post, title: "My post")

      MyRepo.get_by!(Post, [title: "My post"], prefix: "public")

  """
  @callback get_by!(
              queryable :: Ecto.Queryable.t(),
              clauses :: Keyword.t() | map,
              opts :: Keyword.t()
            ) :: Ecto.Schema.t()

  @doc """
  Reloads a given schema or schema list from the database.

  When using with lists, it is expected that all of the structs in the list belong
  to the same schema. Ordering is guaranteed to be kept. Results not found in
  the database will be returned as `nil`.

  ## Example

      MyRepo.reload(post)
      %Post{}

      MyRepo.reload([post1, post2])
      [%Post{}, %Post{}]

      MyRepo.reload([deleted_post, post1])
      [nil, %Post{}]
  """
  @callback reload(
              struct_or_structs :: Ecto.Schema.t() | [Ecto.Schema.t()],
              opts :: Keyword.t()
            ) :: Ecto.Schema.t() | [Ecto.Schema.t() | nil] | nil

  @doc """
  Similar to `c:reload/2`, but raises when something is not found.

  When using with lists, ordering is guaranteed to be kept.

  ## Example

      MyRepo.reload!(post)
      %Post{}

      MyRepo.reload!([post1, post2])
      [%Post{}, %Post{}]
  """
  @callback reload!(struct_or_structs, opts :: Keyword.t()) :: struct_or_structs
            when struct_or_structs: Ecto.Schema.t() | [Ecto.Schema.t()]

  @doc """
  Calculate the given `aggregate`.

  If the query has a limit, offset, distinct or combination set, it will be
  automatically wrapped in a subquery in order to return the
  proper result.

  Any preload or select in the query will be ignored in favor of
  the column being aggregated.

  The aggregation will fail if any `group_by` field is set.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This will be applied to all `from`
      and `join`s in the query that did not have a prefix previously given
      either via the `:prefix` option on `join`/`from` or via `@schema_prefix`
      in the schema. For more information see the "Query Prefix" section of the
      `Ecto.Query` documentation.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

  ## Examples

      # Returns the number of blog posts
      Repo.aggregate(Post, :count)

      # Returns the number of blog posts in the "private" schema path
      # (in Postgres) or database (in MySQL)
      Repo.aggregate(Post, :count, prefix: "private")

  """
  @callback aggregate(
              queryable :: Ecto.Queryable.t(),
              aggregate :: :count,
              opts :: Keyword.t()
            ) :: term | nil

  @doc """
  Calculate the given `aggregate` over the given `field`.

  See `c:aggregate/3` for general considerations and options.

  ## Examples

      # Returns the number of visits per blog post
      Repo.aggregate(Post, :count, :visits)

      # Returns the number of visits per blog post in the "private" schema path
      # (in Postgres) or database (in MySQL)
      Repo.aggregate(Post, :count, :visits, prefix: "private")

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

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This will be applied to all `from`
      and `join`s in the query that did not have a prefix previously given
      either via the `:prefix` option on `join`/`from` or via `@schema_prefix`
      in the schema. For more information see the "Query Prefix" section of the
      `Ecto.Query` documentation.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

  ## Examples

      # checks if any posts exist
      Repo.exists?(Post)

      # checks if any posts exist in the "private" schema path (in Postgres) or
      # database (in MySQL)
      Repo.exists?(Post, schema: "private")

      # checks if any post with a like count greater than 10 exists
      query = from p in Post, where: p.like_count > 10
      Repo.exists?(query)
  """
  @callback exists?(queryable :: Ecto.Queryable.t(), opts :: Keyword.t()) :: boolean()

  @doc """
  Fetches a single result from the query.

  Returns `nil` if no result was found. Raises if more than one entry.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This will be applied to all `from`
      and `join`s in the query that did not have a prefix previously given
      either via the `:prefix` option on `join`/`from` or via `@schema_prefix`
      in the schema. For more information see the "Query Prefix" section of the
      `Ecto.Query` documentation.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

  ## Examples

      Repo.one(from p in Post, join: c in assoc(p, :comments), where: p.id == ^post_id)

      query = from p in Post, join: c in assoc(p, :comments), where: p.id == ^post_id
      Repo.one(query, prefix: "private")
  """
  @callback one(queryable :: Ecto.Queryable.t(), opts :: Keyword.t()) ::
              Ecto.Schema.t() | nil

  @doc """
  Similar to `c:one/2` but raises `Ecto.NoResultsError` if no record was found.

  Raises if more than one entry.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This will be applied to all `from`
      and `join`s in the query that did not have a prefix previously given
      either via the `:prefix` option on `join`/`from` or via `@schema_prefix`
      in the schema. For more information see the "Query Prefix" section of the
      `Ecto.Query` documentation.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.
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

    * `:force` - By default, Ecto won't preload associations that
      are already loaded. By setting this option to true, any existing
      association will be discarded and reloaded.
    * `:in_parallel` - If the preloads must be done in parallel. It can
      only be performed when we have more than one preload and the
      repository is not in a transaction. Defaults to `true`.
    * `:prefix` - the prefix to fetch preloads from. By default, queries
      will use the same prefix as the one in the given collection. This
      option allows the prefix to be changed.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

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
  A user customizable callback invoked for query-based operations.

  This callback can be used to further modify the query and options
  before it is transformed and sent to the database.

  This callback is invoked for all query APIs, including the `stream`
  functions. It is also invoked for `insert_all` if a source query is
  given. It is not invoked for any of the other schema functions.

  ## Examples

  Let's say you want to filter out records that were "soft-deleted"
  (have `deleted_at` column set) from all operations unless an admin
  is running the query; you can define the callback like this:

      @impl true
      def prepare_query(_operation, query, opts) do
        if opts[:admin] do
          {query, opts}
        else
          query = from(x in query, where: is_nil(x.deleted_at))
          {query, opts}
        end
      end

  And then execute the query:

      Repo.all(query)              # only non-deleted records are returned
      Repo.all(query, admin: true) # all records are returned

  The callback will be invoked for all queries, including queries
  made from associations and preloads. It is not invoked for each
  individual join inside a query.
  """
  @callback prepare_query(operation, query :: Ecto.Query.t(), opts :: Keyword.t()) ::
              {Ecto.Query.t(), Keyword.t()}
            when operation: :all | :update_all | :delete_all | :stream | :insert_all

  @doc """
  A user customizable callback invoked to retrieve default options
  for operations.

  This can be used to provide default values per operation that
  have higher precedence than the values given on configuration
  or when starting the repository. It can also be used to set
  query specific options, such as `:prefix`.

  This callback is invoked as the entry point for all repository
  operations. For example, if you are executing a query with preloads,
  this callback will be invoked once at the beginning, but the
  options returned here will be passed to all following operations.
  """
  @callback default_options(operation) :: Keyword.t()
            when operation: :all | :insert_all | :update_all | :delete_all | :stream |
                              :transaction | :insert | :update | :delete | :insert_or_update

  @doc """
  Fetches all entries from the data store matching the given query.

  May raise `Ecto.QueryError` if query validation fails.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This will be applied to all `from`
      and `join`s in the query that did not have a prefix previously given
      either via the `:prefix` option on `join`/`from` or via `@schema_prefix`
      in the schema. For more information see the "Query Prefix" section of the
      `Ecto.Query` documentation.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

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
      in Postgres or the database in MySQL). This will be applied to all `from`
      and `join`s in the query that did not have a prefix previously given
      either via the `:prefix` option on `join`/`from` or via `@schema_prefix`
      in the schema. For more information see the "Query Prefix" section of the
      `Ecto.Query` documentation.

    * `:max_rows` - The number of rows to load from the database as we stream.
      It is supported at least by Postgres and MySQL and defaults to 500.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

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
      in the query and any `@schema_prefix` set in the schema.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for remaining options.

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
  unless a `select` is supplied in the delete query. Note, however,
  not all databases support returning data from DELETEs.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the query and any `@schema_prefix` set in the schema.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for remaining options.

  ## Examples

      MyRepo.delete_all(Post)

      from(p in Post, where: p.id < 10) |> MyRepo.delete_all
  """
  @callback delete_all(queryable :: Ecto.Queryable.t(), opts :: Keyword.t()) ::
              {integer, nil | [term]}

  ## Ecto.Adapter.Schema

  @optional_callbacks insert_all: 3, insert: 2, insert!: 2, update: 2, update!: 2,
                      delete: 2, delete!: 2, insert_or_update: 2, insert_or_update!: 2,
                      prepare_query: 3

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
  before being sent to the database. If the schema primary key has type
  `:id` or `:binary_id`, it will be handled either at the adapter
  or the storage layer. However any other primary key type or autogenerated
  value, like `Ecto.UUID` and timestamps, won't be autogenerated when
  using `c:insert_all/3`. You must set those fields explicitly. This is by
  design as this function aims to be a more direct way to insert data into
  the database without the conveniences of `c:insert/2`. This is also
  consistent with `c:update_all/3` that does not handle auto generated
  values as well.

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
      in Postgres or the database in MySQL). This overrides the prefix set
      in the query and any `@schema_prefix` set in the schema.

    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `:replace_all`, `{:replace_all_except, fields}`, `{:replace, fields}`,
      a keyword list of update instructions or an `Ecto.Query`
      query for updates. See the "Upserts" section for more information.

    * `:conflict_target` - A list of column names to verify for conflicts.
      It is expected those columns to have unique indexes on them that may conflict.
      If none is specified, the conflict target is left up to the database.
      It may also be `{:unsafe_fragment, binary_fragment}` to pass any
      expression to the database without any sanitization, this is useful
      for partial index or index with expressions, such as
      `ON CONFLICT (coalesce(firstname, ""), coalesce(lastname, ""))`.

    * `:placeholders` - A map with placeholders. This feature is not supported
      by all databases. See the "Placeholders" section for more information.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for remaining options.

  ## Source query

  A query can be given instead of a list with entries. This query needs to select
  into a map containing only keys that are available as writeable columns in the
  schema.

  ## Examples

      MyRepo.insert_all(Post, [[title: "My first post"], [title: "My second post"]])

      MyRepo.insert_all(Post, [%{title: "My first post"}, %{title: "My second post"}])

      query = from p in Post,
        join: c in assoc(p, :comments),
        select: %{
          author_id: p.author_id,
          posts: count(p.id, :distinct),
          interactions: sum(p.likes) + count(c.id)
        },
        group_by: p.author_id
      MyRepo.insert_all(AuthorStats, query)

  ## Upserts

  `c:insert_all/3` provides upserts (update or inserts) via the `:on_conflict`
  option. The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting primary key or unique index

    * `:nothing` - ignores the error in case of conflicts

    * `:replace_all` - replace **all** values on the existing row with the values
      in the schema/changeset, including fields not explicitly set in the changeset,
      such as IDs and autogenerated timestamps (`inserted_at` and `updated_at`).
      Do not use this option if you have auto-incrementing primary keys, as they
      will also be replaced. You most likely want to use `{:replace_all_except, [:id]}`
      or `{:replace, fields}` explicitly instead. This option requires a schema

    * `{:replace_all_except, fields}` - same as above except the given fields
      are not replaced. This option requires a schema

    * `{:replace, fields}` - replace only specific columns. This option requires
      `:conflict_target`

    * a keyword list of update instructions - such as the one given to
      `c:update_all/3`, for example: `[set: [title: "new title"]]`

    * an `Ecto.Query` that will act as an `UPDATE` statement, such as the
      one given to `c:update_all/3`

  Upserts map to "ON CONFLICT" on databases like Postgres and "ON DUPLICATE KEY"
  on databases such as MySQL.

  ## Return values

  By default, both Postgres and MySQL will return the number of entries
  inserted on `c:insert_all/3`. However, when the `:on_conflict` option
  is specified, Postgres and MySQL will return different results.

  Postgres will only count a row if it was affected and will
  return 0 if no new entry was added.

  MySQL will return, at a minimum, the number of entries attempted. For example,
  if `:on_conflict` is set to `:nothing`, MySQL will return
  the number of entries attempted to be inserted, even when no entry
  was added.

  Also note that if `:on_conflict` is a query, MySQL will return
  the number of attempted entries plus the number of entries modified
  by the UPDATE query.

  ## Placeholders

  Passing in a map for the `:placeholders` allows you to send less
  data over the wire when you have many entries with the same value
  for a field. To use a placeholder, replace its value in each of your
  entries with `{:placeholder, key}`,  where `key` is the key you
  are using in the `:placeholders` option map. For example:

      placeholders = %{blob: large_blob_of_text(...)}

      entries = [
        %{title: "v1", body: {:placeholder, :blob}},
        %{title: "v2", body: {:placeholder, :blob}}
      ]

      Repo.insert_all(Post, entries, placeholders: placeholders)

  Keep in mind that:

    * placeholders cannot be nested in other values. For example, you
      cannot put a placeholder inside an array. Instead, the whole
      array has to be the placeholder

    * a placeholder key can only be used with columns of the same type

    * placeholders require a database that supports index parameters,
      so they are not currently compatible with MySQL

  """
  @callback insert_all(
              schema_or_source :: binary | {binary, module} | module,
              entries_or_query :: [map | [{atom, term | Ecto.Query.t}]] | Ecto.Query.t,
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

    * `:returning` - selects which fields to return. It accepts a list
      of fields to be returned from the database. When `true`, returns
      all fields. When `false`, no extra fields are returned. It will
      always include all fields in `read_after_writes` as well as any
      autogenerated id. Not all databases support this option and it
      may not be available during upserts. See the "Upserts" section
      for more information.

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the query and any `@schema_prefix` set any schemas. Also, the
      `@schema_prefix` for the parent record will override all default
      `@schema_prefix`s set in any child schemas for associations.

    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `:replace_all`, `{:replace_all_except, fields}`, `{:replace, fields}`,
      a keyword list of update instructions or an `Ecto.Query` query for updates.
      See the "Upserts" section for more information.

    * `:conflict_target` - A list of column names to verify for conflicts.
      It is expected those columns to have unique indexes on them that may conflict.
      If none is specified, the conflict target is left up to the database.
      It may also be `{:unsafe_fragment, binary_fragment}` to pass any
      expression to the database without any sanitization, this is useful
      for partial index or index with expressions, such as
      `ON CONFLICT (coalesce(firstname, ""), coalesce(lastname, ""))`.

    * `:stale_error_field` - The field where stale errors will be added in
      the returning changeset. This option can be used to avoid raising
      `Ecto.StaleEntryError`.

    * `:stale_error_message` - The message to add to the configured
      `:stale_error_field` when stale errors happen, defaults to "is stale".

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

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

    * `:replace_all` - replace **all** values on the existing row with the values
      in the schema/changeset, including fields not explicitly set in the changeset,
      such as IDs and autogenerated timestamps (`inserted_at` and `updated_at`).
      Do not use this option if you have auto-incrementing primary keys, as they
      will also be replaced. You most likely want to use `{:replace_all_except, [:id]}`
      or `{:replace, fields}` explicitly instead. This option requires a schema

    * `{:replace_all_except, fields}` - same as above except the given fields are
      not replaced. This option requires a schema

    * `{:replace, fields}` - replace only specific columns. This option requires
      `:conflict_target`

    * a keyword list of update instructions - such as the one given to
      `c:update_all/3`, for example: `[set: [title: "new title"]]`

    * an `Ecto.Query` that will act as an `UPDATE` statement, such as the
      one given to `c:update_all/3`. Similarly to `c:update_all/3`, auto
      generated values, such as timestamps are not automatically updated.
      If the struct cannot be found, `Ecto.StaleEntryError` will be raised.

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
      including autogenerated fields such as `inserted_at` and `updated_at`:

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
  inserting a struct with associations and using the `:on_conflict` option
  at the same time is not recommended, as Ecto will be unable to actually
  track the proper status of the association.
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

    * `:returning` - selects which fields to return. It accepts a list
      of fields to be returned from the database. When `true`, returns
      all fields. When `false`, no extra fields are returned. It will
      always include all fields in `read_after_writes`. Not all
      databases support this option.

    * `:force` - By default, if there are no changes in the changeset,
      `c:update/2` is a no-op. By setting this option to true, update
      callbacks will always be executed, even if there are no changes
      (including timestamps).

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the query and any `@schema_prefix` set any schemas. Also, the
      `@schema_prefix` for the parent record will override all default
      `@schema_prefix`s set in any child schemas for associations.

    * `:stale_error_field` - The field where stale errors will be added in
      the returning changeset. This option can be used to avoid raising
      `Ecto.StaleEntryError`.

    * `:stale_error_message` - The message to add to the configured
      `:stale_error_field` when stale errors happen, defaults to "is stale".

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

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
      in the query and any `@schema_prefix` set any schemas. Also, the
      `@schema_prefix` for the parent record will override all default
      `@schema_prefix`s set in any child schemas for associations.
    * `:stale_error_field` - The field where stale errors will be added in
      the returning changeset. This option can be used to avoid raising
      `Ecto.StaleEntryError`. Only applies to updates.
    * `:stale_error_message` - The message to add to the configured
      `:stale_error_field` when stale errors happen, defaults to "is stale".
      Only applies to updates.

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

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
      in the query and any `@schema_prefix` set in the schema.

    * `:stale_error_field` - The field where stale errors will be added in
      the returning changeset. This option can be used to avoid raising
      `Ecto.StaleEntryError`.

    * `:stale_error_message` - The message to add to the configured
      `:stale_error_field` when stale errors happen, defaults to "is stale".

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

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

  `c:transaction/2` can be called with both a function of arity
  zero or one. The arity zero function will just be executed as is,
  while the arity one function will receive the repo of the transaction
  as its first argument, similar to `Ecto.Multi.run/3`.

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

  Besides functions, transactions can be used with an `Ecto.Multi` struct.
  A transaction will be started, all operations applied and in case of
  success committed returning `{:ok, changes}`. In case of any errors
  the transaction will be rolled back and
  `{:error, failed_operation, failed_value, changes_so_far}` will be
  returned.

  You can read more about using transactions with `Ecto.Multi` as well as
  see some examples in the `Ecto.Multi` documentation.

  ## Options

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

  ## Examples

      import Ecto.Changeset, only: [change: 2]

      MyRepo.transaction(fn ->
        MyRepo.update!(change(alice, balance: alice.balance - 10))
        MyRepo.update!(change(bob, balance: bob.balance + 10))
      end)

      # When passing a function of arity 1, it receives the repository itself
      MyRepo.transaction(fn repo ->
        repo.insert!(%Post{})
      end)

      # Roll back a transaction explicitly
      MyRepo.transaction(fn ->
        p = MyRepo.insert!(%Post{})
        if not Editor.post_allowed?(p) do
          MyRepo.rollback(:posting_not_allowed)
        end
      end)

      # With Ecto.Multi
      Ecto.Multi.new()
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

  Note that calling `rollback` causes the code in the transaction to stop executing.
  """
  @callback rollback(value :: any) :: no_return
end
