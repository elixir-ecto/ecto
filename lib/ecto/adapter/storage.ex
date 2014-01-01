defmodule Ecto.Adapter.Storage  do
  @moduledoc """
  Specifies the adapter storage API.
  """

  use Behaviour

  @doc """
  Create the repository at its specified `url`.

  If the repository already exists, calling storage_up will be a no-op (:ok).

  ## Examples

    MyRepo.storage_up(Repo)

  """
  defcallback storage_up(Ecto.Repo.t) :: :ok | { :error, any } | no_return
  
end
