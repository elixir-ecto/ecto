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

  @doc """
  Parses an Ecto URL of the following format:
  `ecto://username:password@hostname:port/database?opts=123` where the
  `password`, `port` and `options` are optional.
  """
  def parse_url(url) do
    unless String.match? url, ~r/^[^:\/?#\s]+:\/\// do
      raise Ecto.InvalidURL, url: url, reason: "url should start with a scheme, host should start with //"
    end

    info = URI.parse(url)

    unless is_binary(info.userinfo) and size(info.userinfo) > 0  do
      raise Ecto.InvalidURL, url: url, reason: "url has to contain a username"
    end

    unless String.match? info.path, ~r"^/([^/])+$" do
      raise Ecto.InvalidURL, url: url, reason: "path should be a database name"
    end

    destructure [username, password], String.split(info.userinfo, ":")
    database = String.slice(info.path, 1, size(info.path))
    query = URI.decode_query(info.query || "") |> atomize_keys

    opts = [ username: username,
             hostname: info.host,
             database: database ]

    if password,  do: opts = [password: password] ++ opts
    if info.port, do: opts = [port: info.port] ++ opts

    opts ++ query
  end

  @doc """
  Converts the given binary to underscore format.
  """
  def underscore(""), do: ""

  def underscore(<<h, t :: binary>>) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<h, t, rest :: binary>>, _) when h in ?A..?Z and not t in ?A..?Z do
    <<?_, to_lower_char(h), t>> <> do_underscore(rest, t)
  end

  defp do_underscore(<<h, t :: binary>>, prev) when h in ?A..?Z and not prev in ?A..?Z do
    <<?_, to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<h, t :: binary>>, _) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<>>, _) do
    <<>>
  end

  defp atomize_keys(dict) do
    Enum.map dict, fn {k, v} -> {binary_to_atom(k), v} end
  end

  defp to_lower_char(char) when char in ?A..?Z, do: char + 32
  defp to_lower_char(char), do: char
end
