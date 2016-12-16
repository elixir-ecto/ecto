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
        use Ecto.Repo, otp_app: :my_app
      end

  Could be configured with:

      config :my_app, Repo,
        adapter: Ecto.Adapters.Postgres,
        database: "ecto_simple",
        username: "postgres",
        password: "postgres",
        hostname: "localhost"

  Most of the configuration that goes into the `config` is specific
  to the adapter, so check `Ecto.Adapters.Postgres` documentation
  for more information. However, some configuration is shared across
  all adapters, they are:

    * `:priv` - the directory where to keep repository data, like
      migrations, schema and more. Defaults to "priv/YOUR_REPO".
      It must always point to a subdirectory inside the priv directory.

    * `:url` - an URL that specifies storage information. Read below
      for more information

    * `:loggers` - a list of `{mod, fun, args}` tuples that are
      invoked by adapters for logging queries and other events.
      The given module and function will be called with a log
      entry (see `Ecto.LogEntry`) and the given arguments. The
      invoked function must return the `Ecto.LogEntry` as result.
      The default value is: `[{Ecto.LogEntry, :log, []}]`, which
      will call `Ecto.LogEntry.log/1` that will use Elixir's `Logger`
      in `:debug` mode. You may pass any desired mod-fun-args
      triplet or `[{Ecto.LogEntry, :log, [:info]}]` if you want to
      keep the current behaviour but use another log level.

  ## URLs

  Repositories by default support URLs. For example, the configuration
  above could be rewritten to:

      config :my_app, Repo,
        url: "ecto://postgres:postgres@localhost/ecto_simple"

  The schema can be of any value. The path represents the database name
  while options are simply merged in.

  URLs also support `{:system, "KEY"}` to be given, telling Ecto to load
  the configuration from the system environment instead:

      config :my_app, Repo,
        url: {:system, "DATABASE_URL"}

  ## Shared options

  Almost all of the repository operations below accept the following
  options:

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  Such cases will be explicitly documented as well as any extra option.
  """

  @type t :: module

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Ecto.Repo

      {otp_app, adapter, config} = Ecto.Repo.Supervisor.compile_config(__MODULE__, opts)
      @otp_app otp_app
      @adapter adapter
      @config  config
      @before_compile adapter

      loggers =
        Enum.reduce(config[:loggers] || [Ecto.LogEntry], quote(do: entry), fn
          mod, acc when is_atom(mod) ->
            quote do: unquote(mod).log(unquote(acc))
          {Ecto.LogEntry, :log, [level]}, _acc when not level in [:error, :info, :warn, :debug] ->
            raise ArgumentError, "the log level #{inspect level} is not supported in Ecto.LogEntry"
          {mod, fun, args}, acc ->
            quote do: unquote(mod).unquote(fun)(unquote(acc), unquote_splicing(args))
        end)

      def __adapter__ do
        @adapter
      end

      def __log__(entry) do
        unquote(loggers)
      end

      def config do
        {:ok, config} = Ecto.Repo.Supervisor.runtime_config(:dry_run, __MODULE__, @otp_app, [])
        config
      end

      def start_link(opts \\ []) do
        Ecto.Repo.Supervisor.start_link(__MODULE__, @otp_app, @adapter, opts)
      end

      def stop(pid, timeout \\ 5000) do
        Supervisor.stop(pid, :normal, timeout)
      end

      if function_exported?(@adapter, :transaction, 3) do
        def transaction(fun_or_multi, opts \\ []) do
          Ecto.Repo.Queryable.transaction(@adapter, __MODULE__, fun_or_multi, opts)
        end

        def in_transaction? do
          @adapter.in_transaction?(__MODULE__)
        end

        @spec rollback(term) :: no_return
        def rollback(value) do
          @adapter.rollback(__MODULE__, value)
        end
      end

      def all(queryable, opts \\ []) do
        Ecto.Repo.Queryable.all(__MODULE__, @adapter, queryable, opts)
      end

      def stream(queryable, opts \\ []) do
        Ecto.Repo.Queryable.stream(__MODULE__, @adapter, queryable, opts)
      end

      def get(queryable, id, opts \\ []) do
        Ecto.Repo.Queryable.get(__MODULE__, @adapter, queryable, id, opts)
      end

      def get!(queryable, id, opts \\ []) do
        Ecto.Repo.Queryable.get!(__MODULE__, @adapter, queryable, id, opts)
      end

      def get_by(queryable, clauses, opts \\ []) do
        Ecto.Repo.Queryable.get_by(__MODULE__, @adapter, queryable, clauses, opts)
      end

      def get_by!(queryable, clauses, opts \\ []) do
        Ecto.Repo.Queryable.get_by!(__MODULE__, @adapter, queryable, clauses, opts)
      end

      def one(queryable, opts \\ []) do
        Ecto.Repo.Queryable.one(__MODULE__, @adapter, queryable, opts)
      end

      def one!(queryable, opts \\ []) do
        Ecto.Repo.Queryable.one!(__MODULE__, @adapter, queryable, opts)
      end

      def aggregate(queryable, aggregate, field, opts \\ [])
          when aggregate in [:count, :avg, :max, :min, :sum] and is_atom(field) do
        Ecto.Repo.Queryable.aggregate(__MODULE__, @adapter, queryable, aggregate, field, opts)
      end

      def insert_all(schema_or_source, entries, opts \\ []) do
        Ecto.Repo.Schema.insert_all(__MODULE__, @adapter, schema_or_source, entries, opts)
      end

      def update_all(queryable, updates, opts \\ []) do
        Ecto.Repo.Queryable.update_all(__MODULE__, @adapter, queryable, updates, opts)
      end

      def delete_all(queryable, opts \\ []) do
        Ecto.Repo.Queryable.delete_all(__MODULE__, @adapter, queryable, opts)
      end

      def insert(struct, opts \\ []) do
        Ecto.Repo.Schema.insert(__MODULE__, @adapter, struct, opts)
      end

      def update(struct, opts \\ []) do
        Ecto.Repo.Schema.update(__MODULE__, @adapter, struct, opts)
      end

      def insert_or_update(changeset, opts \\ []) do
        Ecto.Repo.Schema.insert_or_update(__MODULE__, @adapter, changeset, opts)
      end

      def delete(struct, opts \\ []) do
        Ecto.Repo.Schema.delete(__MODULE__, @adapter, struct, opts)
      end

      def insert!(struct, opts \\ []) do
        Ecto.Repo.Schema.insert!(__MODULE__, @adapter, struct, opts)
      end

      def update!(struct, opts \\ []) do
        Ecto.Repo.Schema.update!(__MODULE__, @adapter, struct, opts)
      end

      def insert_or_update!(changeset, opts \\ []) do
        Ecto.Repo.Schema.insert_or_update!(__MODULE__, @adapter, changeset, opts)
      end

      def delete!(struct, opts \\ []) do
        Ecto.Repo.Schema.delete!(__MODULE__, @adapter, struct, opts)
      end

      def preload(struct_or_structs, preloads, opts \\ [])
      def preload(nil, _, _), do: nil
      def preload(struct_or_structs, preloads, opts) do
        Ecto.Repo.Preloader.preload(struct_or_structs, __MODULE__, preloads, opts)
      end

      def load(schema_or_types, data) do
        Ecto.Repo.Schema.load(@adapter, schema_or_types, data)
      end
    end
  end

  @optional_callbacks init: 2

  @doc """
  Returns the adapter tied to the repository.
  """
  @callback __adapter__ :: Ecto.Adapter.t

  @doc """
  A callback invoked by adapters that logs the given action.

  See `Ecto.LogEntry` for more information and `Ecto.Repo` module
  documentation on setting up your own loggers.
  """
  @callback __log__(entry :: Ecto.LogEntry.t) :: Ecto.LogEntry.t

  @doc """
  Returns the adapter configuration stored in the `:otp_app` environment.

  Dynamic configuration is not reflected on this value.
  """
  @callback config() :: Keyword.t

  @doc """
  Starts any connection pooling or supervision and return `{:ok, pid}`
  or just `:ok` if nothing needs to be done.

  Returns `{:error, {:already_started, pid}}` if the repo is already
  started or `{:error, term}` in case anything else goes wrong.

  ## Options

  See the configuration in the moduledoc for options shared between adapters,
  for adapter-specific configuration see the adapter's documentation.
  """
  @callback start_link(opts :: Keyword.t) :: {:ok, pid} |
                            {:error, {:already_started, pid}} |
                            {:error, term}

  @doc """
  A callback executed when the repo starts or when configuration is read.

  The first argument is the context the callback is being invoked. If it
  is called because the Repo supervisor is starting, it will be `:supervisor`.
  It will be `:dry_run` if it is called for reading configuration without
  actually starting a process.

  The second argument is the repository configuration as stored in the
  application environment. It must return `{:ok, keyword}` with the updated
  list of configuration or `:ignore` (only in the `:supervisor` case).
  """
  @callback init(:supervisor | :dry_run, config :: Keyword.t) :: {:ok, Keyword.t} | :ignore

  @doc """
  Shuts down the repository represented by the given pid.
  """
  @callback stop(pid, timeout) :: :ok

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
  @callback get(queryable :: Ecto.Queryable.t, id :: term, opts :: Keyword.t) :: Ecto.Schema.t | nil | no_return

  @doc """
  Similar to `get/3` but raises `Ecto.NoResultsError` if no record was found.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      MyRepo.get!(Post, 42)

  """
  @callback get!(queryable :: Ecto.Queryable.t, id :: term, opts :: Keyword.t) :: Ecto.Schema.t | nil | no_return

  @doc """
  Fetches a single result from the query.

  Returns `nil` if no result was found.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      MyRepo.get_by(Post, title: "My post")

  """
  @callback get_by(queryable :: Ecto.Queryable.t, clauses :: Keyword.t | map, opts :: Keyword.t) :: Ecto.Schema.t | nil | no_return

  @doc """
  Similar to `get_by/3` but raises `Ecto.NoResultsError` if no record was found.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      MyRepo.get_by!(Post, title: "My post")

  """
  @callback get_by!(queryable :: Ecto.Queryable.t, clauses :: Keyword.t | map, opts :: Keyword.t) :: Ecto.Schema.t | nil | no_return

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
  @callback aggregate(queryable :: Ecto.Queryable.t, aggregate :: :avg | :count | :max | :min | :sum,
                      field :: atom, opts :: Keyword.t) :: term | nil

  @doc """
  Fetches a single result from the query.

  Returns `nil` if no result was found. Raises if more than one entry.

  ## Options

  See the "Shared options" section at the module documentation.
  """
  @callback one(queryable :: Ecto.Queryable.t, opts :: Keyword.t) :: Ecto.Schema.t | nil | no_return

  @doc """
  Similar to `one/2` but raises `Ecto.NoResultsError` if no record was found.

  Raises if more than one entry.

  ## Options

  See the "Shared options" section at the module documentation.
  """
  @callback one!(queryable :: Ecto.Queryable.t, opts :: Keyword.t) :: Ecto.Schema.t | no_return

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

      posts = Repo.preload posts, :comments
      posts = Repo.preload posts, comments: :permalinks
      posts = Repo.preload posts, comments: from(c in Comment, order_by: c.published_at)

  """
  @callback preload(struct_or_structs, preloads :: term, opts :: Keyword.t) ::
                    struct_or_structs when struct_or_structs: [Ecto.Schema.t] | Ecto.Schema.t

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
  @callback all(queryable :: Ecto.Query.t, opts :: Keyword.t) :: [Ecto.Schema.t] | no_return

  @doc """
  Returns a lazy enumerable that emits all entries from the data store
  matching the given query. SQL adapters, such as Postgres and MySQL, can only
  enumerate a stream inside a transaction.

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
  @callback stream(queryable :: Ecto.Query.t, opts :: Keyword.t) :: Enum.t

  @doc """
  Inserts all entries into the repository.

  It expects a schema (`MyApp.User`) or a source (`"users"`) or
  both (`{"users", MyApp.User}`) as the first argument. The second
  argument is a list of entries to be inserted, either as keyword
  lists or as maps.

  It returns a tuple containing the number of entries
  and any returned result as second element. If the database
  does not support RETURNING in UPDATE statements or no
  return result was selected, the second element will be `nil`.

  When a schema is given, the values given will be properly dumped
  before being sent to the database. If the schema contains an
  autogenerated ID field, it will be handled either at the adapter
  or the storage layer. However any other autogenerated value, like
  timestamps, won't be autogenerated when using `c:insert_all/3`.
  This is by design as this function aims to be a more direct way
  to insert data into the database without the conveniences of
  `c:insert/2`. This is also consistent with `c:update_all/3` that
  does not handle timestamps as well.

  If a source is given, without a schema, the given fields are passed
  as is to the adapter.

  ## Options

    * `:returning` - selects which fields to return. When `true`,
      returns all fields in the given struct. May be a list of
      fields, where a struct is still returned but only with the
      given fields. Or `false`, where nothing is returned (the default).
      This option is not supported by all databases.
    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL).
    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `:replace_all`, a keyword list of update instructions or an `Ecto.Query`
      query for updates. See the "Upserts" section for more information.
    * `:conflict_target` - Which columns to verify for conflicts. If
      none is specified, the conflict target is left up to the database
      and is usually made of primary keys and/or unique/exclusion constraints.

  See the "Shared options" section at the module documentation for
  remaining options.

  ## Examples

      MyRepo.insert_all(Post, [[title: "My first post"], [title: "My second post"]])
      MyRepo.insert_all(Post, [%{title: "My first post"}, %{title: "My second post"}])

  ## Upserts

  `insert_all` provides upserts (update or inserts) via the `:on_conflict`
  option. The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting primary key or unique index
    * `:nothing` - ignores the error in case of conflicts
    * `:replace_all` - replace all entries in the database by the one being
      currently attempted
    * a keyword list of update instructions - such as the one given to
      `c:update_all/3`, for example: `[set: [title: "new title"]]`
    * an `Ecto.Query` that will act as an `UPDATE` statement, such as the
      one given to `c:update_all/3`

  Upserts map to "ON CONFLICT" on databases like Postgres and "ON DUPLICATE KEY"
  on databases such as MySQL.

  ## Return values

  By default, both Postgres and MySQL return the amount of entries
  inserted on `insert_all`. However, when the `:on_conflict` option
  is specified, Postgres will only return a row if it was affected
  while MySQL returns at least the number of entries attempted.

  For example, if `:on_conflict` is set to `:nothing`, Postgres will
  return 0 if no new entry was added while MySQL will still return
  the amount of entries attempted to be inserted, even if no entry
  was added. Even worse, if `:on_conflict` is query, MySQL will return
  the number of attempted entries plus the number of entries modified
  by the UPDATE query.
  """
  @callback insert_all(schema_or_source :: binary | {binary, Ecto.Schema.t} | Ecto.Schema.t,
                       entries :: [map | Keyword.t], opts :: Keyword.t) :: {integer, nil | [term]} | no_return

  @doc """
  Updates all entries matching the given query with the given values.

  It returns a tuple containing the number of entries
  and any returned result as second element. If the database
  does not support RETURNING in UPDATE statements or no
  return result was selected, the second element will be `nil`.

  Keep in mind this `update_all` will not update autogenerated
  fields like the `updated_at` columns.

  See `Ecto.Query.update/3` for update operations that can be
  performed on fields.

  ## Options

    * `:returning` - selects which fields to return. When `true`,
      returns all fields in the given struct. May be a list of
      fields, where a struct is still returned but only with the
      given fields. Or `false`, where nothing is returned (the default).
      This option is not supported by all databases.
    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the query.

  See the "Shared options" section at the module documentation for
  remaining options.

  ## Examples

      MyRepo.update_all(Post, set: [title: "New title"])

      MyRepo.update_all(Post, inc: [visits: 1])

      from(p in Post, where: p.id < 10)
      |> MyRepo.update_all(set: [title: "New title"])

      from(p in Post, where: p.id < 10, update: [set: [title: "New title"]])
      |> MyRepo.update_all([])

      from(p in Post, where: p.id < 10, update: [set: [title: fragment("?", new_title)]])
      |> MyRepo.update_all([])
  """
  @callback update_all(queryable :: Ecto.Queryable.t, updates :: Keyword.t, opts :: Keyword.t) ::
                       {integer, nil | [term]} | no_return

  @doc """
  Deletes all entries matching the given query.

  It returns a tuple containing the number of entries
  and any returned result as second element. If the database
  does not support RETURNING in DELETE statements or no
  return result was selected, the second element will be `nil`.

  ## Options

    * `:returning` - selects which fields to return. When `true`,
      returns all fields in the given struct. May be a list of
      fields, where a struct is still returned but only with the
      given fields. Or `false`, where nothing is returned (the default).
      This option is not supported by all databases.
    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the query.

  See the "Shared options" section at the module documentation for
  remaining options.

  ## Examples

      MyRepo.delete_all(Post)

      from(p in Post, where: p.id < 10) |> MyRepo.delete_all
  """
  @callback delete_all(queryable :: Ecto.Queryable.t, opts :: Keyword.t) ::
                       {integer, nil | [term]} | no_return

  @doc """
  Inserts a struct or a changeset.

  In case a struct is given, the struct is converted into a changeset
  with all non-nil fields as part of the changeset.

  In case a changeset is given, the changes in the changeset are
  merged with the struct fields, and all of them are sent to the
  database.

  It returns `{:ok, struct}` if the struct has been successfully
  inserted or `{:error, changeset}` if there was a validation
  or a known constraint error.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the struct.
    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `:replace_all`, a keyword list of update instructions or an `Ecto.Query`
      query for updates. See the "Upserts" section for more information.
    * `:conflict_target` - Which columns to verify for conflicts. If
      none is specified, the conflict target is left up to the database
      and is usually made of primary keys and/or unique/exclusion constraints.

  See the "Shared options" section at the module documentation.

  ## Examples

  A typical example is calling `MyRepo.insert/1` with a struct
  and acting on the return value:

      case MyRepo.insert %Post{title: "Ecto is great"} do
        {:ok, struct}       -> # Inserted with success
        {:error, changeset} -> # Something went wrong
      end

  ## Upserts

  `insert_all` provides upserts (update or inserts) via the `:on_conflict`
  option. The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting primary key or unique index
    * `:nothing` - ignores the error in case of conflicts
    * `:replace_all` - replace all entries in the database by the one being
      currently attempted
    * a keyword list of update instructions - such as the one given to
      `c:update_all/3`, for example: `[set: [title: "new title"]]`
    * an `Ecto.Query` that will act as an `UPDATE` statement, such as the
      one given to `c:update_all/3`

  Upserts map to "ON CONFLICT" on databases like Postgres and "ON DUPLICATE KEY"
  on databases such as MySQL.

  As an example, imagine `:title` is marked as a unique column in
  the database:

      # Insert it once
      {:ok, inserted} = MyRepo.insert(%Post{title: "this is unique"})

      # Insert with the same title but do nothing on conflicts.
      # Keep in mind that, although this returns :ok, the returned
      # struct does not reflect the data in the database. For instance,
      # in case of "on_conflict: :nothing", the returned post has no ID.
      {:ok, ignored} = MyRepo.insert(%Post{title: "this is unique"}, on_conflict: :nothing)
      assert ignored.id == nil

      # Now let's insert with the same title but use a query to update
      # a column on conflicts. Although this returns :ok and a struct with
      # the existing ID for successful operations, the other columns may
      # not necessarily reflect the data in the database. In fact, any
      # operation done on `:on_conflict` won't be automatically mapped to
      # the struct.

      # In Postgres (it requires the conflict target for updates):
      on_conflict = [set: [body: "updated"]]
      {:ok, updated} = MyRepo.insert(%Post{title: "this is unique"},
                                     on_conflict: on_conflict, conflict_target: :title)

      # In MySQL (conflict target is not supported):
      on_conflict = [set: [title: "updated"]]
      {:ok, updated} = MyRepo.insert(%Post{id: inserted.id, title: "updated"},
                                     on_conflict: on_conflict)

  """
  @callback insert(struct_or_changeset :: Ecto.Schema.t | Ecto.Changeset.t, opts :: Keyword.t) ::
            {:ok, Ecto.Schema.t} | {:error, Ecto.Changeset.t}

  @doc """
  Updates a changeset using its primary key.

  A changeset is required as it is the only mechanism for
  tracking dirty changes. Only the fields present in the `changes` part
  of the changeset are sent to the database. Any other, in-memory
  changes done to the schema are ignored.

  If the struct has no primary key, `Ecto.NoPrimaryKeyFieldError`
  will be raised.

  It returns `{:ok, struct}` if the struct has been successfully
  updated or `{:error, changeset}` if there was a validation
  or a known constraint error.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:force` - By default, if there are no changes in the changeset,
      `update!/2` is a no-op. By setting this option to true, update
      callbacks will always be executed, even if there are no changes
      (including timestamps).
    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the struct.

  ## Example

      post = MyRepo.get!(Post, 42)
      post = Ecto.Changeset.change post, title: "New title"
      case MyRepo.update post do
        {:ok, struct}       -> # Updated with success
        {:error, changeset} -> # Something went wrong
      end
  """
  @callback update(changeset :: Ecto.Changeset.t, opts :: Keyword.t) ::
            {:ok, Ecto.Schema.t} | {:error, Ecto.Changeset.t}

  @doc """
  Inserts or updates a changeset depending on whether the struct is persisted
  or not.

  The distinction whether to insert or update will be made on the
  `Ecto.Schema.Metadata` field `:state`. The `:state` is automatically set by
  Ecto when loading or building a schema.

  Please note that for this to work, you will have to load existing structs from
  the database. So even if the struct exists, this won't work:

      struct = %Post{id: 'existing_id', ...}
      MyRepo.insert_or_update changeset
      # => {:error, "id already exists"}

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
  @callback insert_or_update(struct_or_changeset :: Ecto.Schema.t | Ecto.Changeset.t, opts :: Keyword.t) ::
            {:ok, Ecto.Schema.t} | {:error, Ecto.Changeset.t}

  @doc """
  Deletes a struct using its primary key.

  If the struct has no primary key, `Ecto.NoPrimaryKeyFieldError`
  will be raised.

  It returns `{:ok, struct}` if the struct has been successfully
  deleted or `{:error, changeset}` if there was a validation
  or a known constraint error.

  ## Options

    * `:prefix` - The prefix to run the query on (such as the schema path
      in Postgres or the database in MySQL). This overrides the prefix set
      in the struct.

  See the "Shared options" section at the module documentation.

  ## Example

      post = MyRepo.get!(Post, 42)
      case MyRepo.delete post do
        {:ok, struct}       -> # Deleted with success
        {:error, changeset} -> # Something went wrong
      end

  """
  @callback delete(struct_or_changeset :: Ecto.Schema.t | Ecto.Changeset.t, opts :: Keyword.t) ::
            {:ok, Ecto.Schema.t} | {:error, Ecto.Changeset.t}

  @doc """
  Same as `insert/2` but returns the struct or raises if the changeset is invalid.
  """
  @callback insert!(struct_or_changeset :: Ecto.Schema.t | Ecto.Changeset.t, opts :: Keyword.t) ::
            Ecto.Schema.t | no_return

  @doc """
  Same as `update/2` but returns the struct or raises if the changeset is invalid.
  """
  @callback update!(changeset :: Ecto.Changeset.t, opts :: Keyword.t) ::
            Ecto.Schema.t | no_return

  @doc """
  Same as `insert_or_update/2` but returns the struct or raises if the changeset
  is invalid.
  """
  @callback insert_or_update!(struct_or_changeset :: Ecto.Schema.t | Ecto.Changeset.t, opts :: Keyword.t) ::
            Ecto.Schema.t | no_return

  @doc """
  Same as `delete/2` but returns the struct or raises if the changeset is invalid.
  """
  @callback delete!(struct_or_changeset :: Ecto.Schema.t | Ecto.Changeset.t, opts :: Keyword.t) ::
            Ecto.Schema.t | no_return

  @doc """
  Runs the given function or `Ecto.Multi` inside a transaction.

  ## Use with function

  If an unhandled error occurs the transaction will be rolled back
  and the error will bubble up from the transaction function.
  If no error occurred the transaction will be committed when the
  function returns. A transaction can be explicitly rolled back
  by calling `rollback/1`, this will immediately leave the function
  and return the value given to `rollback` as `{:error, value}`.

  A successful transaction returns the value returned by the function
  wrapped in a tuple as `{:ok, value}`.

  If `transaction/2` is called inside another transaction, the function
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

      MyRepo.transaction(fn ->
        MyRepo.update!(%{alice | balance: alice.balance - 10})
        MyRepo.update!(%{bob | balance: bob.balance + 10})
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
  @callback transaction(fun_or_multi :: fun | Ecto.Multi.t, opts :: Keyword.t) ::
    {:ok, any} | {:error, any} | {:error, atom, any, %{atom => any}}
  @optional_callbacks [transaction: 2]

  @doc """
  Returns true if the current process is inside a transaction.

  ## Examples

      MyRepo.in_transaction?
      #=> false

      MyRepo.transaction(fn ->
        MyRepo.in_transaction? #=> true
      end)

  """
  @callback in_transaction?() :: boolean
  @optional_callbacks [in_transaction?: 0]

  @doc """
  Rolls back the current transaction.

  The transaction will return the value given as `{:error, value}`.
  """
  @callback rollback(value :: any) :: no_return
  @optional_callbacks [rollback: 1]

  @doc """
  Loads `data` into a struct or a map.

  The first argument can be a schema, or a map (of types) and determines the return value:
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
  @callback load(Ecto.Schema.t | map(), map() | Keyword.t | {list, list}) :: Ecto.Schema.t | map()
end
