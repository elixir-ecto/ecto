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
  defcallback start_link(Ecto.Repo.t, Keyword.t) ::
              {:ok, pid} | :ok | {:error, {:already_started, pid}} | {:error, term}

  @doc """
  Stops any connection pooling or supervision started with `start_link/1`.
  """
  defcallback stop(Ecto.Repo.t) :: :ok

  @doc """
  Fetches all results from the data store based on the given query.
  """
  defcallback all(Ecto.Repo.t, Ecto.Query.t, Keyword.t) :: [term] | no_return

  @doc """
  Stores a single new model in the data store. Return the default values.
  """
  defcallback insert(Ecto.Repo.t, Ecto.Model.t, Keyword.t) :: [Keyword.t] | no_return

  @doc """
  Updates an model using the primary key as key.
  """
  defcallback update(Ecto.Repo.t, Ecto.Model.t, Keyword.t) :: :ok | no_return

  @doc """
  Updates all entities matching the given query with the values given. The
  query will only have where expressions and a single from expression. Returns
  the number of affected entities.
  """
  defcallback update_all(Ecto.Repo.t, Ecto.Query.t, values :: Keyword.t, Keyword.t) :: :integer | no_return

  @doc """
  Deletes an model using the primary key as key.
  """
  defcallback delete(Ecto.Repo.t, Ecto.Model.t, Keyword.t) :: :ok | no_return

  @doc """
  Deletes all entities matching the given query. The query will only have
  where expressions and a single from expression. Returns the number of affected
  entities.
  """
  defcallback delete_all(Ecto.Repo.t, Ecto.Query.t, Keyword.t) :: :integer | no_return
end
