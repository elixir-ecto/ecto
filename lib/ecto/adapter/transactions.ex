defmodule Ecto.Adapter.Transactions  do
  @moduledoc """
  Specifies the transactions API that an adapter is required to implement.
  """

  use Behaviour

  @doc """
  Runs the function on the given repo inside a transaction.
  See `Ecto.Repo.transaction/1`.
  """
  defcallback transaction(Ecto.Repo.t, fun) :: any
end
