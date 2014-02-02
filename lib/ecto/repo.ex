defmodule Ecto.Repo do
  @moduledoc """
  This module is used to define a repository. A repository maps to a data
  store, for example an SQL database. A repository must implement `url/0` and
  set an adapter (see `Ecto.Adapter`) to be used for the repository.

  When used, the following options are allowed:

  * `:adapter` - the adapter to be used for the repository

  * `:env` - configures the repository to support environments

  ## Example

      defmodule MyRepo do
        use Ecto.Repo, adapter: Ecto.Adapters.Postgres

        def url do
          "ecto://postgres:postgres@localhost/postgres"
        end
      end

  Most of the times, we want the repository to work with different
  environments. In such cases, we can pass an `:env` option:

      defmodule MyRepo do
        use Ecto.Repo, adapter: Ecto.Adapters.Postgres, env: Mix.env

        def url(:dev),  do: "ecto://postgres:postgres@localhost/postgres_dev"
        def url(:test), do: "ecto://postgres:postgres@localhost/postgres_test?size=1"
        def url(:prod), do: "ecto://postgres:postgres@localhost/postgres_prod"
      end

  Notice that, when using the environment, developers should implement
  `url/1` which automatically passes the environment instead of `url/0`.

  Note the environment is only used at compilation time. That said, don't
  forget to set the `:build_per_environment` option to true in your Mix
  project definition.
  """

  use Behaviour
  @type t :: module

  @doc false
  defmacro __using__(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    env     = Keyword.get(opts, :env)

    quote do
      use unquote(adapter)
      @behaviour Ecto.Repo
      @env unquote(env)

      import Ecto.Utils, only: [app_dir: 2]

      if @env do
        def url do
          url(@env)
        end
        defoverridable url: 0
      end

      def start_link do
        Ecto.Repo.Backend.start_link(__MODULE__, unquote(adapter))
      end

      def stop do
        Ecto.Repo.Backend.stop(__MODULE__, unquote(adapter))
      end

      def storage_up do
        Ecto.Repo.Backend.storage_up(__MODULE__, unquote(adapter))
      end

      def storage_down do
        Ecto.Repo.Backend.storage_down(__MODULE__, unquote(adapter))
      end

      def get(queryable, id) do
        Ecto.Repo.Backend.get(__MODULE__, unquote(adapter), queryable, id)
      end

      def all(queryable) do
        Ecto.Repo.Backend.all(__MODULE__, unquote(adapter), queryable)
      end

      def create(entity) do
        Ecto.Repo.Backend.create(__MODULE__, unquote(adapter), entity)
      end

      def update(entity) do
        Ecto.Repo.Backend.update(__MODULE__, unquote(adapter), entity)
      end

      defmacro update_all(queryable, values) do
        Ecto.Repo.Backend.update_all(__MODULE__, unquote(adapter), queryable, values)
      end

      def delete(entity) do
        Ecto.Repo.Backend.delete(__MODULE__, unquote(adapter), entity)
      end

      def delete_all(queryable) do
        Ecto.Repo.Backend.delete_all(__MODULE__, unquote(adapter), queryable)
      end

      def transaction(fun) do
        Ecto.Repo.Backend.transaction(__MODULE__, unquote(adapter), fun)
      end

      def adapter do
        unquote(adapter)
      end

      def __repo__ do
        true
      end

      def query_apis do
        [Ecto.Query.API]
      end

      defoverridable [query_apis: 0]
    end
  end

  @doc """
  Should return the Ecto URL to be used for the repository. A URL is of the
  following format: `ecto://username:password@hostname:port/database?opts=123`
  where the `password`, `port` and `options` are optional. This function must be
  implemented by the user.
  """
  defcallback url() :: String.t

  @doc """
  Starts any connection pooling or supervision and return `{ :ok, pid }`
  or just `:ok` if nothing needs to be done.

  Returns `{ :error, { :already_started, pid } }` if the repo already
  started or `{ :error, term }` in case anything else goes wrong.
  """
  defcallback start_link() :: { :ok, pid } | :ok |
                              { :error, { :already_started, pid } } |
                              { :error, term }

  @doc """
  Stops any connection pooling or supervision started with `start_link/1`.
  """
  defcallback stop() :: :ok

  @doc """
  Create the storage in the data store and return `:ok` if it was created
  successfully.

  Returns `{ :error, :already_up }` if the storage has already been created or
  `{ :error, term }` in case anything else goes wrong.
  """
  defcallback storage_up() :: :ok | { :error, :already_up } | { :error, term }

  @doc """
  Drop the storage in the data store and return `:ok` if it was dropped
  successfully.

  Returns `{ :error, :already_down }` if the storage has already been dropped or
  `{ :error, term }` in case anything else goes wrong.
  """
  defcallback storage_down() :: :ok | { :error, :already_down } | { :error, term }

  @doc """
  Fetches a single entity from the data store where the primary key matches the
  given id. id should be an integer or a string that can be cast to an
  integer. Returns `nil` if no result was found. If the entity in the queryable
  has no primary key `Ecto.NoPrimaryKey` will be raised. `Ecto.AdapterError`
  will be raised if there is an adapter error.
  """
  defcallback get(Ecto.Queryable.t, integer) :: Ecto.Entity.t | nil | no_return

  @doc """
  Fetches all results from the data store based on the given query. May raise
  `Ecto.QueryError` if query validation fails. `Ecto.AdapterError` will be
  raised if there is an adapter error.

  ## Example

      # Fetch all post titles
      query = from p in Post,
           select: p.title
      MyRepo.all(query)
  """
  defcallback all(Ecto.Query.t) :: [Ecto.Entity.t] | no_return

  @doc """
  Stores a single new entity in the data store and returns its stored
  representation. May raise `Ecto.AdapterError` if there is an adapter error.

  ## Example

      post = Post.new(title: "Ecto is great", text: "really, it is")
        |> MyRepo.create
  """
  defcallback create(Ecto.Entity.t) :: Ecto.Entity.t | no_return

  @doc """
  Updates an entity using the primary key as key. If the entity has no primary
  key `Ecto.NoPrimaryKey` will be raised. `Ecto.AdapterError` will be raised if
  there is an adapter error.

  ## Example

      [post] = from p in Post, where: p.id == 42
      post = post.title("New title")
      MyRepo.update(post)
  """
  defcallback update(Ecto.Entity.t) :: :ok | no_return

  @doc """
  Updates all entities matching the given query with the given values.
  `Ecto.AdapterError` will be raised if there is an adapter error.

  ## Examples

      MyRepo.update_all(Post, title: "New title")

      MyRepo.update_all(p in Post, visits: p.visits + 1)

      from(p in Post, where: p.id < 10)
      |> MyRepo.update_all(title: "New title")
  """
  defmacrocallback update_all(Macro.t, Keyword.t) :: integer | no_return

  @doc """
  Deletes an entity using the primary key as key. If the entity has no primary
  key `Ecto.NoPrimaryKey` will be raised. `Ecto.AdapterError` will be raised if
  there is an adapter error.

  ## Example

      [post] = from p in Post, where: p.id == 42
      MyRepo.delete(post)
  """
  defcallback delete(Ecto.Entity.t) :: :ok | no_return

  @doc """
  Deletes all entities matching the given query with the given values.
  `Ecto.AdapterError` will be raised if there is an adapter error.

  ## Examples

      MyRepo.delete_all(Post)

      from(p in Post, where: p.id < 10) |> MyRepo.delete_all
  """
  defcallback delete_all(Ecto.Queryable.t) :: integer | no_return

  @doc """
  Runs the given function inside a transaction. If an unhandled error occurs the
  transaction will be rolled back. If no error occurred the transaction will be
  commited when the function returns. A transaction can be explicitly rolled
  back by throwing `:ecto_rollback` or `{ :ecto_rollback`, term }, this will
  leave immediately leave the given function but the throw will not bubble up.
  Transactions can be nested.

  ## Examples

      MyRepo.transaction(fn ->
        MyRepo.update(alice.update_balance(&(&1 - 10))
        MyRepo.update(bob.update_balance(&(&1 + 10))
      end)

      # In the following example only the comment will be rolled back
      MyRepo.transaction(fn ->
        MyRepo.create(Post.new)

        MyRepo.transaction(fn ->
          MyRepo.create(Comment.new)
          raise "error"
        end)
      end)

      # Roll back a transaction explicitly
      MyRepo.transaction(fn ->
        p = MyRepo.create(Post.new)
        if not Editor.post_allowed?(p) do
          throw :ecto_rollback
        end
      end)

  """
  defcallback transaction(fun) :: any

  @doc """
  Returns the adapter tied to the repository.
  """
  defcallback adapter() :: Ecto.Adapter.t

  @doc """
  Returns the supported query APIs.
  """
  defcallback query_apis :: [module]
end
