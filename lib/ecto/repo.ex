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

  use Behaviour
  @type t :: module

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Ecto.Repo

      {otp_app, adapter, config} = Ecto.Repo.Config.parse(__MODULE__, opts)
      @otp_app otp_app
      @adapter adapter
      @config  config
      @before_compile adapter

      require Logger
      @log_level config[:log_level] || :debug

      def config do
        Ecto.Repo.Config.config(@otp_app, __MODULE__)
      end

      def start_link do
        @adapter.start_link(__MODULE__, config())
      end

      def stop do
        @adapter.stop(__MODULE__)
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

      def update_all(queryable, updates, opts \\ []) do
        Ecto.Repo.Queryable.update_all(__MODULE__, @adapter, queryable, updates, opts)
      end

      def delete_all(queryable, opts \\ []) do
        Ecto.Repo.Queryable.delete_all(__MODULE__, @adapter, queryable, opts)
      end

      def insert(model, opts \\ []) do
        Ecto.Repo.Model.insert(__MODULE__, @adapter, model, opts)
      end

      def update(model, opts \\ []) do
        Ecto.Repo.Model.update(__MODULE__, @adapter, model, opts)
      end

      def delete(model, opts \\ []) do
        Ecto.Repo.Model.delete(__MODULE__, @adapter, model, opts)
      end

      def insert!(model, opts \\ []) do
        Ecto.Repo.Model.insert!(__MODULE__, @adapter, model, opts)
      end

      def update!(model, opts \\ []) do
        Ecto.Repo.Model.update!(__MODULE__, @adapter, model, opts)
      end

      def delete!(model, opts \\ []) do
        Ecto.Repo.Model.delete!(__MODULE__, @adapter, model, opts)
      end

      def preload(model_or_models, preloads) do
        Ecto.Repo.Preloader.preload(model_or_models, __MODULE__, preloads)
      end

      def adapter do
        @adapter
      end

      def __repo__ do
        true
      end

      def log(entry) do
        Logger.unquote(@log_level)(fn ->
          {_entry, iodata} = Ecto.LogEntry.to_iodata(entry)
          iodata
        end)
      end

      defoverridable [log: 1]
    end
  end

  @doc """
  Returns the adapter tied to the repository.
  """
  defcallback adapter() :: Ecto.Adapter.t

  @doc """
  Simply returns true to mark this module as a repository.
  """
  defcallback __repo__ :: true

  @doc """
  Returns the adapter configuration stored in the `:otp_app` environment.
  """
  defcallback config() :: Keyword.t

  @doc """
  Starts any connection pooling or supervision and return `{:ok, pid}`
  or just `:ok` if nothing needs to be done.

  Returns `{:error, {:already_started, pid}}` if the repo already
  started or `{:error, term}` in case anything else goes wrong.
  """
  defcallback start_link() :: {:ok, pid} | :ok |
                              {:error, {:already_started, pid}} |
                              {:error, term}

  @doc """
  Stops any connection pooling or supervision started with `start_link/1`.
  """
  defcallback stop() :: :ok

  @doc """
  Fetches a single model from the data store where the primary key matches the
  given id.

  Returns `nil` if no result was found. If the model in the queryable
  has no primary key `Ecto.NoPrimaryKeyError` will be raised.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000)
    * `:log` - When false, does not log the query

  """
  defcallback get(Ecto.Queryable.t, term, Keyword.t) :: Ecto.Model.t | nil | no_return

  @doc """
  Similar to `get/3` but raises `Ecto.NoResultsError` if no record was found.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  """
  defcallback get!(Ecto.Queryable.t, term, Keyword.t) :: Ecto.Model.t | nil | no_return

  @doc """
  Fetches a single result from the query.

  Returns `nil` if no result was found.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Example

      MyRepo.get_by(Post, title: "My post")

  """
  defcallback get_by(Ecto.Queryable.t, Keyword.t, Keyword.t) :: Ecto.Model.t | nil | no_return

  @doc """
  Similar to `get_by/3` but raises `Ecto.NoResultsError` if no record was found.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Example

      MyRepo.get_by!(Post, title: "My post")

  """
  defcallback get_by!(Ecto.Queryable.t, Keyword.t, Keyword.t) :: Ecto.Model.t | nil | no_return

  @doc """
  Fetches a single result from the query.

  Returns `nil` if no result was found.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  """
  defcallback one(Ecto.Queryable.t, Keyword.t) :: Ecto.Model.t | nil | no_return

  @doc """
  Similar to `one/2` but raises `Ecto.NoResultsError` if no record was found.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  """
  defcallback one!(Ecto.Queryable.t, Keyword.t) :: Ecto.Model.t | nil | no_return

  @doc """
  Preloads all associations on the given model or models.

  `preloads` is a list of associations that can be nested in rose
  tree structure:

      node :: atom | {atom, node} | [node]

  In case the association was already loaded, preload won't attempt
  to reload it.
  """
  defcallback preload([Ecto.Model.t] | Ecto.Model.t, preloads :: term) ::
                      [Ecto.Model.t] | Ecto.Model.t

  @doc """
  Fetches all entries from the data store matching the given query.

  May raise `Ecto.QueryError` if query validation fails.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Example

      # Fetch all post titles
      query = from p in Post,
           select: p.title
      MyRepo.all(query)
  """
  defcallback all(Ecto.Query.t, Keyword.t) :: [Ecto.Model.t] | no_return

  @doc """
  Updates all entries matching the given query with the given values.

  It returns a tuple containing the number of entries
  and any returned result as second element. If the database
  does not support RETURNING in UPDATE statements or no
  return result was selected, the second element will be nil.

  This operation does not run the model `before_update` and
  `after_update` callbacks.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Examples

      MyRepo.update_all(Post, set: [title: "New title"])

      MyRepo.update_all(Post, inc: [visits: 1])

      from(p in Post, where: p.id < 10)
      |> MyRepo.update_all(set: [title: "New title"])

      from(p in Post, where: p.id < 10, update: [set: [title: "New title"]])
      |> MyRepo.update_all([])
  """
  defcallback update_all(Macro.t, Keyword.t, Keyword.t) :: {integer, nil} | no_return

  @doc """
  Deletes all entries matching the given query.

  It returns a tuple containing the number of entries
  and any returned result as second element. If the database
  does not support RETURNING in DELETE statements or no
  return result was selected, the second element will be nil.

  This operation does not run the model `before_delete` and
  `after_delete` callbacks.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Examples

      MyRepo.delete_all(Post)

      from(p in Post, where: p.id < 10) |> MyRepo.delete_all
  """
  defcallback delete_all(Ecto.Queryable.t, Keyword.t) :: {integer, nil} | no_return

  @doc """
  Inserts a model or a changeset.

  In case a model is given, the model is converted into a changeset
  with all model non-virtual fields as part of the changeset.

  In case a changeset is given, the changes in the changeset are
  merged with the model fields, and all of them are sent to the
  database.

  If any `before_insert` or `after_insert` callback is registered
  in the given model, they will be invoked with the changeset.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Example

      post = MyRepo.insert! %Post{title: "Ecto is great"}

  """
  defcallback insert!(Ecto.Model.t | Ecto.Changeset.t, Keyword.t) :: Ecto.Model.t | no_return

  @doc """
  Updates a model or changeset using its primary key.

  In case a model is given, the model is converted into a changeset
  with all model non-virtual fields as part of the changeset. For this
  reason, it is preferred to use changesets as they perform dirty
  tracking and avoid sending data that did not change to the database
  over and over. In case there are no changes in the changeset, no
  data is sent to the database at all.

  In case a changeset is given, only the changes in the changeset
  will be updated, leaving all the other model fields intact.

  If any `before_update` or `after_update` callback are registered
  in the given model, they will be invoked with the changeset.

  If the model has no primary key, `Ecto.NoPrimaryKeyError` will be raised.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Example

      post = MyRepo.get!(Post, 42)
      post = %{post | title: "New title"}
      MyRepo.update!(post)
  """
  defcallback update!(Ecto.Model.t | Ecto.Changeset.t, Keyword.t) :: Ecto.Model.t | no_return

  @doc """
  Deletes a model using its primary key.

  If any `before_delete` or `after_delete` callback are registered
  in the given model, they will be invoked with the changeset.

  If the model has no primary key, `Ecto.NoPrimaryKeyError` will be raised.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log the query

  ## Example

      [post] = MyRepo.all(from(p in Post, where: p.id == 42))
      MyRepo.delete!(post)

  """
  defcallback delete!(Ecto.Model.t, Keyword.t) :: Ecto.Model.t | no_return

  @doc """
  Runs the given function inside a transaction.

  If an unhandled error occurs the transaction will be rolled back
  and the error will bubble up from the transaction function.
  If no error occurred the transaction will be commited when the
  function returns. A transaction can be explicitly rolled back
  by calling `rollback/1`, this will immediately leave the function
  and return the value given to `rollback` as `{:error, value}`.

  A successful transaction returns the value returned by the function
  wrapped in a tuple as `{:ok, value}`. Transactions can be nested.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log begin/commit/rollback queries

  ## Examples

      MyRepo.transaction(fn ->
        MyRepo.update!(%{alice | balance: alice.balance - 10})
        MyRepo.update!(%{bob | balance: bob.balance + 10})
      end)

      # In the following example only the comment will be rolled back
      MyRepo.transaction(fn ->
        MyRepo.insert!(%Post{})

        MyRepo.transaction(fn ->
          MyRepo.insert!(%Comment{})
          raise "error"
        end)
      end)

      # Roll back a transaction explicitly
      MyRepo.transaction(fn ->
        p = MyRepo.insert!(%Post{})
        if not Editor.post_allowed?(p) do
          MyRepo.rollback(:posting_not_allowed)
        end
      end)

  """
  defcallback transaction(Keyword.t, fun) :: {:ok, any} | {:error, any}

  @doc """
  Rolls back the current transaction.

  The transaction will return the value given as `{:error, value}`.
  """
  defcallback rollback(any) :: no_return

  @doc ~S"""
  Enables logging of adapter actions such as sending queries to the database.

  By default writes to Logger but can be overriden to customize behaviour.

  ## Examples

  The default implementation of the `log/1` function is shown below:

      def log(entry) do
        Logger.debug(fn ->
          {_entry, iodata} = Ecto.LogEntry.to_iodata(entry)
          iodata
        end)
      end

  """
  defcallback log(Ecto.LogEntry.t) :: any
end
