defmodule Ecto.Adapter do
  @moduledoc """
  This module specifies the adapter API that an adapter is required to
  implement.
  """

  use Behaviour

  @doc """
  All adapters are automatically used into the udnerlying repository
  module.
  """
  defmacro __using__(Macro.t) :: Macro.

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
      MyRepo.create(post)
  """
  defcallback create(atom, term) :: :ok | { :error, term }
end
