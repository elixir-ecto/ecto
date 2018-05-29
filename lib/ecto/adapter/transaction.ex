defmodule Ecto.Adapter.Transaction do
  @moduledoc """
  Specifies the adapter transactions API.
  """

  @type adapter_meta :: Ecto.Adapter.adapter_meta()

  @doc """
  Runs the given function inside a transaction.

  Returns `{:ok, value}` if the transaction was successful where `value`
  is the value return by the function or `{:error, value}` if the transaction
  was rolled back where `value` is the value given to `rollback/1`.
  """
  @callback transaction(adapter_meta, options :: Keyword.t(), function :: fun) ::
              {:ok, any} | {:error, any}

  @doc """
  Returns true if the given process is inside a transaction.
  """
  @callback in_transaction?(adapter_meta) :: boolean

  @doc """
  Rolls back the current transaction.

  The transaction will return the value given as `{:error, value}`.

  See `c:Ecto.Repo.rollback/1`.
  """
  @callback rollback(adapter_meta, value :: any) :: no_return
end
