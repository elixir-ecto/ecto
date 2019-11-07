defmodule Ecto.Adapter.Storage do
  @moduledoc """
  Specifies the adapter storage API.
  """

  @doc """
  Creates the storage given by options.

  Returns `:ok` if it was created successfully.

  Returns `{:error, :already_up}` if the storage has already been created or
  `{:error, term}` in case anything else goes wrong.

  ## Examples

      storage_up(username: "postgres",
                 database: "ecto_test",
                 hostname: "localhost")

  """
  @callback storage_up(options :: Keyword.t) :: :ok | {:error, :already_up} | {:error, term}

  @doc """
  Drops the storage given by options.

  Returns `:ok` if it was dropped successfully.

  Returns `{:error, :already_down}` if the storage has already been dropped or
  `{:error, term}` in case anything else goes wrong.

  ## Examples

      storage_down(username: "postgres",
                   database: "ecto_test",
                   hostname: "localhost")

  """
  @callback storage_down(options :: Keyword.t) :: :ok | {:error, :already_down} | {:error, term}
  
  @doc """
  Returns the status of a storage given by options.

  Can return `:up`, `:down` or `{:error, term}` in case anything goes wrong.

  ## Examples

      storage_status(username: "postgres",
                     database: "ecto_test",
                     hostname: "localhost")

  """
  @callback storage_status(options :: Keyword.t()) :: :up | :down | {:error, term()}
end
