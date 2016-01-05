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
      migrations, schema and more. Defaults to "priv/YOUR_REPO"

    * `:url` - an URL that specifies storage information. Read below
      for more information

  ## URLs

  Repositories by default support URLs. For example, the configuration
  above could be rewriten to:

      config :my_app, Repo,
        url: "ecto://postgres:postgres@localhost/ecto_simple"

  The schema can be of any value. The path represents the database name
  while options are simply merged in.

  URLs also support `{:system, "KEY"}` to be given, telling Ecto to load
  the configuration from the system environment instead:

      config :my_app, Repo,
        url: {:system, "DATABASE_URL"}

  """

  @type t :: module

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Ecto.Repo

      {otp_app, adapter, pool, config} = Ecto.Repo.Supervisor.parse_config(__MODULE__, opts)
      @otp_app otp_app
      @adapter adapter
      @config  config
      @pool pool
      @query_cache config[:query_cache] || __MODULE__
      @before_compile adapter

      require Logger
      @log_level config[:log_level] || :debug

      def config do
        Ecto.Repo.Supervisor.config(__MODULE__, @otp_app, [])
      end

      def start_link(opts \\ []) do
        Ecto.Repo.Supervisor.start_link(__MODULE__, @otp_app, @adapter, opts)
      end

      def stop(pid, timeout \\ 5000) do
        Supervisor.stop(pid, timeout)
      end

      def transaction(opts \\ [], fun) when is_list(opts) do
        @adapter.transaction(__MODULE__, opts, fun)
      end

      def rollback(value) do
        @adapter.rollback(__MODULE__, value)
      end

      def all(queryable, opts \\ []) do
        Ecto.Repo.Queryable.all(__MODULE__, @adapter, queryable, opts)
      end

      def get(queryable, id, opts \\ []) do
        Ecto.Repo.Queryable.get(__MODULE__, @adapter, queryable, id, opts)
      end

      def get!(queryable, id, opts \\ []) do
        Ecto.Repo.Queryable.get!(__MODULE__, @adapter, queryable, id, opts)
      end

      def get_by(queryable, clauses, opts \\ []) do
        Ecto.Repo.Queryable.get_by(__MODULE__, unquote(adapter), queryable, clauses, opts)
      end

      def get_by!(queryable, clauses, opts \\ []) do
        Ecto.Repo.Queryable.get_by!(__MODULE__, unquote(adapter), queryable, clauses, opts)
      end

      def one(queryable, opts \\ []) do
        Ecto.Repo.Queryable.one(__MODULE__, @adapter, queryable, opts)
      end

      def one!(queryable, opts \\ []) do
        Ecto.Repo.Queryable.one!(__MODULE__, @adapter, queryable, opts)
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

      def preload(struct_or_structs, preloads) do
        Ecto.Repo.Preloader.preload(struct_or_structs, __MODULE__, preloads)
      end

      def __adapter__ do
        @adapter
      end

      def __query_cache__ do
        @query_cache
      end

      def __repo__ do
        true
      end

      def __pool__ do
        @pool
      end

      def log(entry) do
        Logger.unquote(@log_level)(fn ->
          {_entry, iodata} = Ecto.LogEntry.to_iodata(entry)
          iodata
        end, ecto_conn_pid: entry.connection_pid)
      end

      defoverridable [log: 1, __pool__: 0]
    end
  end

  @doc """
  Returns the adapter tied to the repository.
  """
  @callback __adapter__ :: Ecto.Adapter.t

  @doc """
  Simply returns true to mark this module as a repository.
  """
  @callback __repo__ :: true

  @doc """
  Returns the pool information this repository should run under.
  """
  @callback __pool__ :: {name :: atom, opts :: Keyword.t}

  @doc """
  Returns the name of the ETS table used for query caching.

  The name can be configured with the `:query_cache` option.
  """
  @callback __query_cache__ :: atom

  @doc """
  Returns the adapter configuration stored in the `:otp_app` environment.
  """
  @callback config() :: Keyword.t

  @doc """
  Starts any connection pooling or supervision and return `{:ok, pid}`
  or just `:ok` if nothing needs to be done.

  Returns `{:error, {:already_started, pid}}` if the repo already
  started or `{:error, term}` in case anything else goes wrong.
  """
  @callback start_link() :: {:ok, pid} |
                              {:error, {:already_started, pid}} |
                              {:error, term}

  @doc """
  Shuts down the repository represented by the given pid.
  """
  @callback stop(pid, timeout) :: :ok

  @doc """
  Fetches a single struct from the data store where the primary key matches the
  given id.

  Returns `nil` if no result was found. If the struct in the queryable
  has no primary key `Ecto.NoPrimaryKeyFieldError` will be raised.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  """
  @callback get(Ecto.Queryable.t, term, Keyword.t) :: Ecto.Schema.t | nil | no_return

  @doc """
  Similar to `get/3` but raises `Ecto.NoResultsError` if no record was found.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  """
  @callback get!(Ecto.Queryable.t, term, Keyword.t) :: Ecto.Schema.t | nil | no_return

  @doc """
  Fetches a single result from the query.

  Returns `nil` if no result was found.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Example

      MyRepo.get_by(Post, title: "My post")

  """
  @callback get_by(Ecto.Queryable.t, Keyword.t | Map.t, Keyword.t) :: Ecto.Schema.t | nil | no_return

  @doc """
  Similar to `get_by/3` but raises `Ecto.NoResultsError` if no record was found.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Example

      MyRepo.get_by!(Post, title: "My post")

  """
  @callback get_by!(Ecto.Queryable.t, Keyword.t | Map.t, Keyword.t) :: Ecto.Schema.t | nil | no_return

  @doc """
  Fetches a single result from the query.

  Returns `nil` if no result was found. Raises if more than one entry.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);;
    * `:log` - When false, does not log the query

  """
  @callback one(Ecto.Queryable.t, Keyword.t) :: Ecto.Schema.t | nil | no_return

  @doc """
  Similar to `one/2` but raises `Ecto.NoResultsError` if no record was found.

  Raises if more than one entry.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);;
    * `:log` - When false, does not log the query

  """
  @callback one!(Ecto.Queryable.t, Keyword.t) :: Ecto.Schema.t | nil | no_return

  @doc """
  Preloads all associations on the given struct or structs.

  This is similar to `Ecto.Query.preload/3` except it allows
  you to preload structs after they have been fetched from the
  database.

  In case the association was already loaded, preload won't attempt
  to reload it.

  ## Examples

      posts = Repo.preload posts, :comments
      posts = Repo.preload posts, comments: :permalinks
      posts = Repo.preload posts, comments: from(c in Comment, order_by: c.published_at)

  """
  @callback preload([Ecto.Schema.t] | Ecto.Schema.t, preloads :: term) ::
                      [Ecto.Schema.t] | Ecto.Schema.t

  @doc """
  Fetches all entries from the data store matching the given query.

  May raise `Ecto.QueryError` if query validation fails.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Example

      # Fetch all post titles
      query = from p in Post,
           select: p.title
      MyRepo.all(query)
  """
  @callback all(Ecto.Query.t, Keyword.t) :: [Ecto.Schema.t] | no_return

  @doc """
  Inserts all entries into the repository.

  It expects a schema (`MyApp.User`) or a source (`"users"` or
  `{"prefix", "users"}`) as first argument. The second argument
  is a list of entries to be inserted, either as keyword lists
  or as maps.

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
  """
  @callback insert_all(binary | {binary | nil, binary} | Ecto.Schema.t,
                       [map | Keyword.t], opts :: Keyword.t) :: {integer, nil} | no_return

  @doc """
  Updates all entries matching the given query with the given values.

  It returns a tuple containing the number of entries
  and any returned result as second element. If the database
  does not support RETURNING in UPDATE statements or no
  return result was selected, the second element will be nil.

  Keep in mind this `update_all` will not update autogenerated
  fields like the `updated_at` columns.

  See `Ecto.Query.update/3` for update operations that can be
  performed on fields.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Examples

      MyRepo.update_all(Post, set: [title: "New title"])

      MyRepo.update_all(Post, inc: [visits: 1])

      from(p in Post, where: p.id < 10)
      |> MyRepo.update_all(set: [title: "New title"])

      from(p in Post, where: p.id < 10, update: [set: [title: "New title"]])
      |> MyRepo.update_all([])
  """
  @callback update_all(Macro.t, Keyword.t, Keyword.t) :: {integer, nil} | no_return

  @doc """
  Deletes all entries matching the given query.

  It returns a tuple containing the number of entries
  and any returned result as second element. If the database
  does not support RETURNING in DELETE statements or no
  return result was selected, the second element will be nil.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Examples

      MyRepo.delete_all(Post)

      from(p in Post, where: p.id < 10) |> MyRepo.delete_all
  """
  @callback delete_all(Ecto.Queryable.t, Keyword.t) :: {integer, nil} | no_return

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

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Example

      case MyRepo.insert %Post{title: "Ecto is great"} do
        {:ok, struct}       -> # Inserted with success
        {:error, changeset} -> # Something went wrong
      end

  """
  @callback insert(Ecto.Schema.t | Ecto.Changeset.t, Keyword.t) ::
              {:ok, Ecto.Schema.t} | {:error, Ecto.Changeset.t}

  @doc """
  Updates a changeset using its primary key.

  A changeset is required as it is the only for mechanism for
  tracking dirty changes.

  If the struct has no primary key, `Ecto.NoPrimaryKeyFieldError`
  will be raised.

  It returns `{:ok, struct}` if the struct has been successfully
  updated or `{:error, changeset}` if there was a validation
  or a known constraint error.

  ## Options

    * `:force` - By default, if there are no changes in the changeset,
      `update!/2` is a no-op. By setting this option to true, update
      callbacks will always be executed, even if there are no changes
      (including timestamps).
    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Example

      post = MyRepo.get!(Post, 42)
      post = Ecto.Changeset.change post, title: "New title"
      case MyRepo.update post do
        {:ok, struct}       -> # Updated with success
        {:error, changeset} -> # Something went wrong
      end
  """
  @callback update(Ecto.Changeset.t, Keyword.t) ::
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
  @callback insert_or_update(Ecto.Changeset.t, Keyword.t) ::
              {:ok, Ecto.Schema.t} | {:error, Ecto.Changeset.t}

  @doc """
  Deletes a struct using its primary key.

  If the struct has no primary key, `Ecto.NoPrimaryKeyFieldError`
  will be raised.

  It returns `{:ok, struct}` if the struct has been successfully
  deleted or `{:error, changeset}` if there was a validation
  or a known constraint error.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Example

      [post] = MyRepo.all(from(p in Post, where: p.id == 42))
      case MyRepo.delete post do
        {:ok, struct}       -> # Deleted with success
        {:error, changeset} -> # Something went wrong
      end

  """
  @callback delete(Ecto.Schema.t, Keyword.t) ::
              {:ok, Ecto.Schema.t} | {:error, Ecto.Changeset.t}

  @doc """
  Same as `insert/2` but returns the struct or raises if the changeset is invalid.
  """
  @callback insert!(Ecto.Schema.t, Keyword.t) :: Ecto.Schema.t | no_return

  @doc """
  Same as `update/2` but returns the struct or raises if the changeset is invalid.
  """
  @callback update!(Ecto.Schema.t, Keyword.t) :: Ecto.Schema.t | no_return

  @doc """
  Same as `insert_or_update/2` but returns the struct or raises if the changeset
  is invalid.
  """
  @callback insert_or_update!(Ecto.Changeset.t, Keyword.t) ::
              Ecto.Schema.t | no_return

  @doc """
  Same as `delete/2` but returns the struct or raises if the changeset is invalid.
  """
  @callback delete!(Ecto.Schema.t, Keyword.t) :: Ecto.Schema.t | no_return

  @doc """
  Runs the given function inside a transaction.

  If an unhandled error occurs the transaction will be rolled back
  and the error will bubble up from the transaction function.
  If no error occurred the transaction will be commited when the
  function returns. A transaction can be explicitly rolled back
  by calling `rollback/1`, this will immediately leave the function
  and return the value given to `rollback` as `{:error, value}`.

  A successful transaction returns the value returned by the function
  wrapped in a tuple as `{:ok, value}`.

  If `transaction/2` is called inside another transaction, the function
  is simply executed, without wrapping the new transaction call in any
  way. If there is an error in the inner transaction and the error is
  rescued, or the inner transaction is rolled back, the whole outer
  transaction is marked as tainted, guaranteeing nothing will be comitted.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log begin/commit/rollback queries

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

  """
  @callback transaction(Keyword.t, fun) :: {:ok, any} | {:error, any}

  @doc """
  Rolls back the current transaction.

  The transaction will return the value given as `{:error, value}`.
  """
  @callback rollback(any) :: no_return

  @doc ~S"""
  Enables logging of adapter actions such as sending queries to the database.

  By default writes to Logger but can be overriden to customize behaviour.

  ## Examples

  The default implementation of the `log/1` function is shown below:

      def log(entry) do
        Logger.debug(fn ->
          {_entry, iodata} = Ecto.LogEntry.to_iodata(entry)
          iodata
        end, ecto_conn_pid: entry.connection_pid)
      end

  """
  @callback log(Ecto.LogEntry.t) :: any
end
