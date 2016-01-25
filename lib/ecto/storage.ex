defmodule Ecto.Storage do
  @moduledoc """
  Convenience functions around the data store of a repository.
  """

  @doc """
  Creates the storage in the data store.

  Returns `:ok` if it was created successfully.

  Returns `{:error, :already_up}` if the storage has already been created or
  `{:error, term}` in case anything else goes wrong.
  """
  @spec up(Ecto.Repo.t) :: :ok | {:error, :already_up} | {:error, term}
  def up(repo) do
    repo.__adapter__.storage_up(repo.config)
  end

  @doc """
  Drops the storage in the data store.

  Returns `:ok` if it was dropped successfully.

  Returns `{:error, :already_down}` if the storage has already been dropped or
  `{:error, term}` in case anything else goes wrong.
  """
  @spec down(Ecto.Repo.t) :: :ok | {:error, :already_down} | {:error, term}
  def down(repo) do
    repo.__adapter__.storage_down(repo.config)
  end
end
