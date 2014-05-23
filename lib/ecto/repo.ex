defmodule Ecto.Repo do
  @moduledoc """
  This module is used to define a repository. A repository maps to a data
  store, for example an SQL database. A repository must implement `conf/0` and
  set an adapter (see `Ecto.Adapter`) to be used for the repository.

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

  Note the environment is only used at compilation time. That said, don't
  forget to set the `:build_per_environment` option to true in your Mix
  project definition.
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

      import Ecto.Utils, only: [app_dir: 2, parse_url: 1]

      if @env do
        def conf do
          conf(@env)
        end
        defoverridable conf: 0
      end

      def start_link do
        Ecto.Repo.Backend.start_link(__MODULE__, unquote(adapter))
      end

      def stop do
        Ecto.Repo.Backend.stop(__MODULE__, unquote(adapter))
      end

      def get(queryable, id, opts \\ []) do
        Ecto.Repo.Backend.get(__MODULE__, unquote(adapter), queryable, id, opts)
      end

      def get!(queryable, id, opts \\ []) do
        Ecto.Repo.Backend.get!(__MODULE__, unquote(adapter), queryable, id, opts)
      end

      def one(queryable, opts \\ []) do
        Ecto.Repo.Backend.one(__MODULE__, unquote(adapter), queryable, opts)
      end

      def one!(queryable, opts \\ []) do
        Ecto.Repo.Backend.one!(__MODULE__, unquote(adapter), queryable, opts)
      end

      def all(queryable, opts \\ []) do
        Ecto.Repo.Backend.all(__MODULE__, unquote(adapter), queryable, opts)
      end

      def insert(model, opts \\ []) do
        Ecto.Repo.Backend.insert(__MODULE__, unquote(adapter), model, opts)
      end

      def update(model, opts \\ []) do
        Ecto.Repo.Backend.update(__MODULE__, unquote(adapter), model, opts)
      end

      defmacro update_all(queryable, values, opts \\ []) do
        Ecto.Repo.Backend.update_all(__MODULE__, unquote(adapter), queryable,
                                     values, opts)
      end

      def delete(model, opts \\ []) do
        Ecto.Repo.Backend.delete(__MODULE__, unquote(adapter), model, opts)
      end

      def delete_all(queryable, opts \\ []) do
        Ecto.Repo.Backend.delete_all(__MODULE__, unquote(adapter), queryable, opts)
      end

      def transaction(opts \\ [], fun) do
        Ecto.Repo.Backend.transaction(__MODULE__, unquote(adapter), opts, fun)
      end

      def rollback(value \\ nil) do
        Ecto.Repo.Backend.rollback(__MODULE__, unquote(adapter), value)
      end

      def adapter do
        unquote(adapter)
      end

      def __repo__ do
        true
      end

      def log(arg, fun) do
        fun.()
      end

      def query_apis do
        [Ecto.Query.API]
      end

      defoverridable [log: 2, query_apis: 0]
    end
  end

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
  given id. Returns `nil` if no result was found. If the model in the queryable
  has no primary key `Ecto.NoPrimaryKey` will be raised. `Ecto.AdapterError`
  will be raised if there is an adapter error.

  ## Options
    `:timeout` - The time in milliseconds to wait for the call to finish,
                 `:infinity` will wait indefinitely (default: 5000);
  """
  defcallback get(Ecto.Queryable.t, term, Keyword.t) :: Ecto.Model.t | nil | no_return

  @doc """
  Fetches all results from the data store based on the given query. May raise
  `Ecto.QueryError` if query validation fails. `Ecto.AdapterError` will be
  raised if there is an adapter error.

  ## Options
    `:timeout` - The time in milliseconds to wait for the call to finish,
                 `:infinity` will wait indefinitely (default: 5000);

  ## Example

      # Fetch all post titles
      query = from p in Post,
           select: p.title
      MyRepo.all(query)
  """
  defcallback all(Ecto.Query.t, Keyword.t) :: [Ecto.Model.t] | no_return

  @doc """
  Stores a single new model in the data store and returns its stored
  representation. May raise `Ecto.AdapterError` if there is an adapter error.

  ## Options
    `:timeout` - The time in milliseconds to wait for the call to finish,
                 `:infinity` will wait indefinitely (default: 5000);

  ## Example

      post = %Post{title: "Ecto is great", text: "really, it is"}
             |> MyRepo.insert
  """
  defcallback insert(Ecto.Model.t, Keyword.t) :: Ecto.Model.t | no_return

  @doc """
  Updates an model using the primary key as key. If the model has no primary
  key `Ecto.NoPrimaryKey` will be raised. `Ecto.AdapterError` will be raised if
  there is an adapter error.

  ## Options
    `:timeout` - The time in milliseconds to wait for the call to finish,
                 `:infinity` will wait indefinitely (default: 5000);

  ## Example

      [post] = from p in Post, where: p.id == 42
      post = post.title("New title")
      MyRepo.update(post)
  """
  defcallback update(Ecto.Model.t, Keyword.t) :: :ok | no_return

  @doc """
  Updates all entities matching the given query with the given values.
  `Ecto.AdapterError` will be raised if there is an adapter error.

  ## Options
    `:timeout` - The time in milliseconds to wait for the call to finish,
                 `:infinity` will wait indefinitely (default: 5000);

  ## Examples

      MyRepo.update_all(Post, title: "New title")

      MyRepo.update_all(p in Post, visits: p.visits + 1)

      from(p in Post, where: p.id < 10)
      |> MyRepo.update_all(title: "New title")
  """
  defmacrocallback update_all(Macro.t, Keyword.t, Keyword.t) :: integer | no_return

  @doc """
  Deletes an model using the primary key as key. If the model has no primary
  key `Ecto.NoPrimaryKey` will be raised. `Ecto.AdapterError` will be raised if
  there is an adapter error.

  ## Options
    `:timeout` - The time in milliseconds to wait for the call to finish,
                 `:infinity` will wait indefinitely (default: 5000);

  ## Example

      [post] = MyRepo.all(from(p in Post, where: p.id == 42))
      MyRepo.delete(post)
  """
  defcallback delete(Ecto.Model.t, Keyword.t) :: :ok | no_return

  @doc """
  Deletes all entities matching the given query with the given values.
  `Ecto.AdapterError` will be raised if there is an adapter error.

  ## Options
    `:timeout` - The time in milliseconds to wait for the call to finish,
                 `:infinity` will wait indefinitely (default: 5000);

  ## Examples

      MyRepo.delete_all(Post)

      from(p in Post, where: p.id < 10) |> MyRepo.delete_all
  """
  defcallback delete_all(Ecto.Queryable.t, Keyword.t) :: integer | no_return

  @doc """
  Runs the given function inside a transaction. If an unhandled error occurs the
  transaction will be rolled back. If no error occurred the transaction will be
  commited when the function returns. A transaction can be explicitly rolled
  back by calling `rollback!`, this will immediately leave the function and
  return the value given to `rollback!` as `{:error, value}`. A successful
  transaction returns the value returned by the function wrapped in a tuple as
  `{:ok, value}`. Transactions can be nested.

  ## Options
    `:timeout` - The time in milliseconds to wait for the call to finish,
                 `:infinity` will wait indefinitely (default: 5000);

  ## Examples

      MyRepo.transaction(fn ->
        MyRepo.update(alice.update_balance(&(&1 - 10))
        MyRepo.update(bob.update_balance(&(&1 + 10))
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
          MyRepo.rollback!
        end
      end)

  """
  defcallback transaction(Keyword.t, fun) :: {:ok, any} | {:error, any}

  @doc """
  Rolls back the current transaction. See `rollback/1`.
  """
  defcallback rollback() :: no_return

  @doc """
  Rolls back the current transaction. The transaction will return the value
  given as `{:error, value}`.
  """
  defcallback rollback(any) :: no_return

  @doc """
  Returns the adapter tied to the repository.
  """
  defcallback adapter() :: Ecto.Adapter.t

  @doc """
  Enables logging and debugging of adapter actions such as sending queries to
  the database. Should be overridden to customize behaviour.

  ## Examples

      def log({:query, sql}, fun) do
        {time, result} = :timer.tc(fun)
        Logger.log({sql, time})
        result
      end

      def log(_arg, fun), do: fun.()

  """
  defcallback log(any, (() -> any)) :: any

  @doc """
  Returns the supported query APIs. Should be overridden to customize.
  """
  defcallback query_apis() :: [module]
end
