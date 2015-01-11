defmodule Ecto.Repo do
  @moduledoc """
  Defines a repository.

  A repository maps to a data store, for example an SQL database.
  A repository must implement `conf/0` and set an adapter (see `Ecto.Adapter`)
  to be used for the repository.

  When used, the following options are allowed:

  * `:adapter` - the adapter to be used for the repository

  * `:env` - configures the repository to support environments

  ## Example

      defmodule MyRepo do
        use Ecto.Repo, adapter: Ecto.Adapters.Postgres

        def conf do
          parse_url "ecto://postgres:postgres@localhost/postgres"
        end
      end

  Most of the time, we want the repository to work with different
  environments. In such cases, we can pass an `:env` option:

      defmodule MyRepo do
        use Ecto.Repo, adapter: Ecto.Adapters.Postgres, env: Mix.env

        def conf(env), do: parse_url url(env)

        defp url(:dev),  do: "ecto://postgres:postgres@localhost/postgres_dev"
        defp url(:test), do: "ecto://postgres:postgres@localhost/postgres_test?size=1"
        defp url(:prod), do: "ecto://postgres:postgres@localhost/postgres_prod"
      end

  Notice that, when using the environment, developers should implement
  `conf/1` which automatically passes the environment instead of `conf/0`.

  Note the environment is only used at compilation time. That said, make
  sure the `:build_per_environment` option is set to true (the default)
  in your Mix project configuration.
  """

  use Behaviour
  @type t :: module

  @doc false
  defmacro __using__(opts) do
    adapter = Macro.expand(Keyword.fetch!(opts, :adapter), __CALLER__)
    env     = Keyword.get(opts, :env)

    unless Code.ensure_loaded?(adapter) do
      raise ArgumentError, message: "Adapter #{inspect adapter} was not compiled, " <>
                                    "ensure its driver is included as a dependency of your project"
    end

    quote do
      use unquote(adapter)
      @behaviour Ecto.Repo
      @env unquote(env)
      require Logger

      import Ecto.Utils, only: [parse_url: 1, parse_url: 2]
      import Application, only: [app_dir: 2]

      if @env do
        def conf do
          conf(@env)
        end
        defoverridable conf: 0
      end

      def start_link do
        unquote(adapter).start_link(__MODULE__, conf)
      end

      def stop do
        unquote(adapter).stop(__MODULE__)
      end

      def transaction(opts \\ [], fun) when is_list(opts) do
        unquote(adapter).transaction(__MODULE__, opts, fun)
      end

      def rollback(value) do
        unquote(adapter).rollback(__MODULE__, value)
      end

      def all(queryable, opts \\ []) do
        Ecto.Repo.Queryable.all(__MODULE__, unquote(adapter), queryable, opts)
      end

      def get(queryable, id, opts \\ []) do
        Ecto.Repo.Queryable.get(__MODULE__, unquote(adapter), queryable, id, opts)
      end

      def get!(queryable, id, opts \\ []) do
        Ecto.Repo.Queryable.get!(__MODULE__, unquote(adapter), queryable, id, opts)
      end

      def one(queryable, opts \\ []) do
        Ecto.Repo.Queryable.one(__MODULE__, unquote(adapter), queryable, opts)
      end

      def one!(queryable, opts \\ []) do
        Ecto.Repo.Queryable.one!(__MODULE__, unquote(adapter), queryable, opts)
      end

      defmacro update_all(queryable, values, opts \\ []) do
        Ecto.Repo.Queryable.update_all(__MODULE__, unquote(adapter), queryable,
                                       values, opts)
      end

      def delete_all(queryable, opts \\ []) do
        Ecto.Repo.Queryable.delete_all(__MODULE__, unquote(adapter), queryable, opts)
      end

      def insert(model, opts \\ []) do
        Ecto.Repo.Model.insert(__MODULE__, unquote(adapter), model, opts)
      end

      def update(model, opts \\ []) do
        Ecto.Repo.Model.update(__MODULE__, unquote(adapter), model, opts)
      end

      def delete(model, opts \\ []) do
        Ecto.Repo.Model.delete(__MODULE__, unquote(adapter), model, opts)
      end

      def preload(model_or_models, preloads) do
        Ecto.Repo.Preloader.preload(model_or_models, __MODULE__, preloads)
      end

      def adapter do
        unquote(adapter)
      end

      def __repo__ do
        true
      end

      # TODO: Should we keep this as overridable?
      def log({:query, sql}, fun) do
        {time, result} = :timer.tc(fun)
        Logger.debug fn -> [sql, " (", inspect(time), "µs)"] end
        result
      end

      def log(_arg, fun) do
        fun.()
      end

      defoverridable [log: 2]
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
  Should return the database options that will be given to the adapter. Often
  used in conjunction with `parse_url/1`. This function must be implemented by
  the user.
  """
  defcallback conf() :: Keyword.t

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
      `:infinity` will wait indefinitely (default: 5000);

  """
  defcallback get(Ecto.Queryable.t, term, Keyword.t) :: Ecto.Model.t | nil | no_return


  @doc """
  Similar to `get/3` but raises `Ecto.NotSingleResult` if no record was found.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);

  """
  defcallback get!(Ecto.Queryable.t, term, Keyword.t) :: Ecto.Model.t | nil | no_return

  @doc """
  Fetches a single result from the query.

  Returns `nil` if no result was found.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);

  """
  defcallback one(Ecto.Queryable.t, Keyword.t) :: Ecto.Model.t | nil | no_return

  @doc """
  Similar to `one/3` but raises `Ecto.NotSingleResult` if no record was found.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);

  """
  defcallback one!(Ecto.Queryable.t, Keyword.t) :: Ecto.Model.t | nil | no_return

  @doc """
  Preloads all associations on the given model or models.

  `preloads` is a list of associations that can be nested in rose
  tree structure:

      node :: atom | {atom, node} | [node]

  """
  defcallback preload([Ecto.Model.t] | Ecto.Model.t, preloads :: term) ::
                      [Ecto.Model.t] | Ecto.Model.t

  @doc """
  Fetches all entries from the data store matching the given query.

  May raise `Ecto.QueryError` if query validation fails.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);

  ## Example

      # Fetch all post titles
      query = from p in Post,
           select: p.title
      MyRepo.all(query)
  """
  defcallback all(Ecto.Query.t, Keyword.t) :: [Ecto.Model.t] | no_return

  @doc """
  Updates all entries matching the given query with the given values.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);

  ## Examples

      MyRepo.update_all(Post, title: "New title")

      MyRepo.update_all(p in Post, visits: p.visits + 1)

      from(p in Post, where: p.id < 10)
      |> MyRepo.update_all(title: "New title")
  """
  defmacrocallback update_all(Macro.t, Keyword.t, Keyword.t) :: integer | no_return

  @doc """
  Deletes all entries matching the given query.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);

  ## Examples

      MyRepo.delete_all(Post)

      from(p in Post, where: p.id < 10) |> MyRepo.delete_all
  """
  defcallback delete_all(Ecto.Queryable.t, Keyword.t) :: integer | no_return

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

  ## Example

      post = MyRepo.insert %Post{title: "Ecto is great"}

  """
  defcallback insert(Ecto.Model.t | Ecto.Changeset.t, Keyword.t) :: Ecto.Model.t | no_return

  @doc """
  Updates a model or changeset using its primary key.

  In case a model is given, the model is converted into a changeset
  with all model non-virtual fields as part of the changeset.

  In case a changeset is given, only the changes in the changeset
  will be updated, leaving all the other model fields intact.

  If any `before_update` or `after_update` callback are registered
  in the given model, they will be invoked with the changeset.

  If the model has no primary key, `Ecto.NoPrimaryKeyError` will be raised.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);

  ## Example

      post = MyRepo.get!(Post, 42)
      post = %{post | title: "New title"}
      MyRepo.update(post)
  """
  defcallback update(Ecto.Model.t | Ecto.Changeset.t, Keyword.t) :: Ecto.Model.t | no_return

  @doc """
  Deletes a model using its primary key.

  If any `before_delete` or `after_delete` callback are registered
  in the given model, they will be invoked with the changeset.

  If the model has no primary key, `Ecto.NoPrimaryKeyError` will be raised.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);

  ## Example

      [post] = MyRepo.all(from(p in Post, where: p.id == 42))
      MyRepo.delete(post)

  """
  defcallback delete(Ecto.Model.t, Keyword.t) :: Ecto.Model.t | no_return

  @doc """
  Runs the given function inside a transaction.

  If an unhandled error occurs the transaction will be rolled back.
  If no error occurred the transaction will be commited when the
  function returns. A transaction can be explicitly rolled back
  by calling `rollback/1`, this will immediately leave the function
  and return the value given to `rollback` as `{:error, value}`.

  A successful transaction returns the value returned by the function
  wrapped in a tuple as `{:ok, value}`. Transactions can be nested.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000);

  ## Examples

      MyRepo.transaction(fn ->
        MyRepo.update(%{alice | balance: alice.balance - 10})
        MyRepo.update(%{bob | balance: bob.balance + 10})
      end)

      # In the following example only the comment will be rolled back
      MyRepo.transaction(fn ->
        MyRepo.insert(%Post{})

        MyRepo.transaction(fn ->
          MyRepo.insert(%Comment{})
          raise "error"
        end)
      end)

      # Roll back a transaction explicitly
      MyRepo.transaction(fn ->
        p = MyRepo.insert(%Post{})
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

  @doc """
  Enables logging and debugging of adapter actions such as sending queries to
  the database.

  By default writes to Logger but can be overriden to customize behaviour.

  You must return the result of calling the passed in function.

  ## Examples

      def log({:query, sql}, fun) do
        {time, result} = :timer.tc(fun)
        Logger.debug inspect{sql, time}
        result
      end

      def log(_arg, fun), do: fun.()

  """
  defcallback log({:query, String.t} | :begin | :commit | :rollback, (() -> any)) :: any
end
