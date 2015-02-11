defmodule Ecto.Adapter.Transaction  do
  @moduledoc """
  Specifies the adapter transactions API.
  """

  use Behaviour

  @doc """
  Runs the given function inside a transaction. Returns `{:ok, value}` if the
  transaction was successful where `value` is the value return by the function
  or `{:error, value}` if the transaction was rolled back where `value` is the
  value given to `rollback/1`.

  See `Ecto.Repo.transaction/1`.
  """
  defcallback transaction(Ecto.Repo.t, Keyword.t, fun) :: {:ok, any} | {:error, any}

  @doc """
  Rolls back the current transaction. The transaction will return the value
  given as `{:error, value}`.

  See `Ecto.Repo.rollback/1`.
  """
  defcallback rollback(Ecto.Repo.t, any) :: no_return
end
