defmodule Ecto.Adapter do
  @moduledoc """
  This module specifies the adapter API that an adapter is required to
  implement.
  """

  use Behaviour

  @type t :: module

  @doc """
  The callback invoked in case the adapter needs to inject code.
  """
  defmacrocallback __before_compile__(Macro.Env.t) :: Macro.t

  @doc """
  Starts any connection pooling or supervision and return `{:ok, pid}`
  or just `:ok` if nothing needs to be done.

  Returns `{:error, {:already_started, pid}}` if the repo already
  started or `{:error, term}` in case anything else goes wrong.
  """
  defcallback start_link(repo :: Ecto.Repo.t, options :: Keyword.t) ::
              {:ok, pid} | :ok | {:error, {:already_started, pid}} | {:error, term}

  @doc """
  Stops any connection pooling or supervision started with `start_link/1`.
  """
  defcallback stop(repo :: Ecto.Repo.t) :: :ok

  @doc """
  Fetches all results from the data store based on the given query.
  """
  defcallback all(repo :: Ecto.Repo.t, query :: Ecto.Query.t,
                  params :: list(), opts :: Keyword.t) :: [[term]] | no_return

  @doc """
  Updates all entities matching the given query with the values given. The
  query shall only have `where` expressions and a single `from` expression. Returns
  the number of affected entities.
  """
  defcallback update_all(repo :: Ecto.Repo.t, query :: Ecto.Query.t,
                         updates :: Keyword.t, params :: list(),
                         opts :: Keyword.t) :: integer | no_return

  @doc """
  Deletes all entities matching the given query.

  The query shall only have `where` expressions and a `from` expression.
  Returns the number of affected entities.
  """
  defcallback delete_all(repo :: Ecto.Repo.t, query :: Ecto.Query.t,
                         params :: list(), opts :: Keyword.t) :: integer | no_return

  @doc """
  Inserts a single new model in the data store.
  """
  defcallback insert(repo :: Ecto.Repo.t, source :: binary,
                     fields :: Keyword.t, returning :: [atom],
                     opts :: Keyword.t) :: {:ok, Keyword.t} | no_return

  @doc """
  Updates a single model with the given filters.

  While `filter` can be any record column, it is expected that
  at least the primary key (or any other key that uniquely
  identifies an existing record) to be given as filter. Therefore,
  in case there is no record matching the given filters,
  `{:error, :stale}` is returned.
  """
  defcallback update(repo :: Ecto.Repo.t, source :: binary,
                     fields :: Keyword.t, filter :: Keyword.t,
                     returning :: [atom], opts :: Keyword.t) ::
                     {:ok, Keyword.t} | {:error, :stale} | no_return

  @doc """
  Deletes a sigle model with the given filters.

  While `filter` can be any record column, it is expected that
  at least the primary key (or any other key that uniquely
  identifies an existing record) to be given as filter. Therefore,
  in case there is no record matching the given filters,
  `{:error, :stale}` is returned.
  """
  defcallback delete(repo :: Ecto.Repo.t, source :: binary,
                     filter :: Keyword.t, opts :: Keyword.t) ::
                     {:ok, Keyword.t} | {:error, :stale} | no_return
end
