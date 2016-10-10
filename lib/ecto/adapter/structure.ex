defmodule Ecto.Adapter.Structure  do
  @moduledoc """
  Specifies the adapter structure API.
  """

  @doc """
  Dumps the given structure.

  The path will be looked in the `config` under :dump_path or
  default to the structure path inside `default`.

  Returns `:ok` if it was loaded successfully, an error tuple otherwise.

  ## Examples

      structure_dump("priv/repo", username: "postgres",
                                  database: "ecto_test",
                                  hostname: "localhost")

  """
  @callback structure_dump(default :: String.t, config :: Keyword.t) ::
            {:ok, String.t} | {:error, term}

  @doc """
  Loads the given structure.

  The path will be looked in the `config` under :dump_path or
  default to the structure path inside `default`.

  Returns `:ok` if it was loaded successfully, an error tuple otherwise.

  ## Examples

      structure_load("priv/repo", username: "postgres",
                                  database: "ecto_test",
                                  hostname: "localhost")

  """
  @callback structure_load(default :: String.t, config :: Keyword.t) ::
            {:ok, String.t} | {:error, term}
end
