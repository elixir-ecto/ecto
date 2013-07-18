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
  Should fetch results from the data store based on the given query.

  ## Example

      # Fetch all post titles
      query = from p in Post,
           select: post.title
      MyRepo.fetch(query)
  """
  defcallback fetch(atom, term) :: { :ok, term } | { :error, term }

  @doc """
  Stores a single new entity in the data store.

  ## Example

      # Fetch all post titles
      post = Post.new(title: "Ecto is great", text: "really, it is")
        |> MyRepo.create
  """
  defcallback create(atom, tuple) :: { :ok, tuple } | { :error, term }

  @doc """
  Updates an entity using the primary key as key, if the entity has no primary
  key `Ecto.NoPrimaryKey` will be raised.
  """
  defcallback update(atom, tuple) :: { :ok, tuple } | { :error, term }

  @doc """
  Deletes an entity using the primary key as key, if the entity has no primary
  key `Ecto.NoPrimaryKey` will be raised.
  """
  defcallback delete(atom, tuple) :: :ok | { :error, term }
end
