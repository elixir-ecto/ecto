defmodule Ecto.Adapter.Storage  do
  @moduledoc """
  Specifies the adapter storage API.
  """

  use Behaviour

  @doc """
  Create the storage in the data store and return `:ok` if it was created
  successfully.

  Returns `{ :error, :already_up }` if the storage has already been created or
  `{ :error, term }` in case anything else goes wrong.

  ## Examples

    MyAdapter.storage_up([ username: postgres,
                           database: 'ecto_test',
                           hostname: 'localhost'])

  """
  defcallback storage_up(Keyword.t) :: :ok | { :error, :already_up } | { :error, term }
end
