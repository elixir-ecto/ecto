defmodule Ecto.Utils do
  @moduledoc """
  Convenience functions used throughout Ecto and
  imported into users modules.
  """

  @doc """
  Receives an `app` and returns the absolute `path` from
  the application directory.
  """
  @spec app_dir(atom, String.t) :: String.t | { :error, term }
  def app_dir(app, path) when is_atom(app) and is_binary(path) do
    case :code.lib_dir(app) do
      { :error, _ } = error -> error
      lib when is_list(lib) -> Path.join(String.from_char_list!(lib), path)
    end
  end
end
