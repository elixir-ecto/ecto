defmodule Ecto.Adapter do
  @moduledoc """
  This module specifies the adapter API that an adapter is required to
  implement.
  """

  use Behaviour

  @type t :: module

  @doc """
  The callback invoked when the adapter is used.
  """
  defmacrocallback __using__(opts :: Keyword.t) :: Macro.t

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
                  params :: map(), each_row :: (term -> term),
                  opts :: Keyword.t) :: [term] | no_return

  @doc """
  Updates all entities matching the given query with the values given. The
  query shall only have `where` expressions and a single `from` expression. Returns
  the number of affected entities.
  """
  defcallback update_all(repo :: Ecto.Repo.t, query :: Ecto.Query.t,
                         filter :: Keyword.t, params :: map(),
                         opts :: Keyword.t) :: :integer | no_return

  @doc """
  Deletes all entities matching the given query.

  The query shall only have `where` expressions and a `from` expression.
  Returns the number of affected entities.
  """
  defcallback delete_all(repo :: Ecto.Repo.t, query :: Ecto.Query.t,
                         params :: map(), opts :: Keyword.t) :: :integer | no_return

  @doc """
  Stores a single new model in the data store.
  """
  defcallback insert(repo :: Ecto.Repo.t, source :: binary,
                     fields :: Keyword.t, opts :: Keyword.t) :: tuple | no_return

  @doc """
  Updates a model using the primary key as key.
  """
  defcallback update(repo :: Ecto.Repo.t, source :: binary, filter :: Keyword.t,
                     fields :: Keyword.t, opts :: Keyword.t) :: tuple | no_return

  @doc """
  Deletes a model using the primary key as key.
  """
  defcallback delete(repo :: Ecto.Repo.t, source :: binary,
                     filter :: Keyword.t, opts :: Keyword.t) :: :ok | no_return
end
