defmodule Ecto.Adapter.Transactions  do
  @moduledoc """
  Specifies the adapter transactions API.
  """

  use Behaviour

  @doc """
  Runs the function on the given repo inside a transaction.
  See `Ecto.Repo.transaction/1`.
  """
  defcallback transaction(Ecto.Repo.t, fun) :: any
end
