defmodule Ecto.Adapter do
  @moduledoc """
  This module specifies the adapter API that an adapter is required to
  implement.
  """

  use Behaviour

  @doc """
  Should start any connection pooling or supervision and return `{ :ok, pid }`
  or just `:ok` if nothing needs to be done. Return `{ :error, error }` if
  something went wrong.
  """
  defcallback start_link(atom) :: { :ok, pid } | :ok | { :error, term }

  @doc """
  Should stop any connection pooling or supervision started with `start_link/1`.
  """
  defcallback stop(atom) :: :ok

  @doc """
  Should fetch all results from the data store based on the given query.
  """
  defcallback all(atom, term) :: { :ok, term } | { :error, term }

  @doc """
  Should store a single new entity in the data store.
  """
  defcallback create(atom, tuple) :: { :ok, tuple } | { :error, term }

  @doc """
  Should update an entity using the primary key as key.
  """
  defcallback update(atom, tuple) :: { :ok, tuple } | { :error, term }

  @doc """
  Should delete an entity using the primary key as key.
  """
  defcallback delete(atom, tuple) :: :ok | { :error, term }
end
