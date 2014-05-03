defmodule Ecto.Utils do
  @moduledoc """
  Convenience functions used throughout Ecto and
  imported into users modules.
  """

  @doc """
  Receives an `app` and returns the absolute `path` from
  the application directory. It fails if the application
  name is invalid.
  """
  @spec app_dir(atom, String.t) :: String.t | no_return
  def app_dir(app, path) when is_atom(app) and is_binary(path) do
    case :code.lib_dir(app) do
      lib when is_list(lib) -> Path.join(String.from_char_data!(lib), path)
      {:error, :bad_name} -> raise "invalid application #{inspect app}"
    end
  end
end
