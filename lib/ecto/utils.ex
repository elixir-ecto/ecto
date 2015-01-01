defmodule Ecto.Utils do
  @doc """
  Parses an Ecto URL of the following format:
  `ecto://username:password@hostname:port/database?opts=123` where all options
  but the database is optional.

  If `username` is not specified, `$PGUSER` or `$USER` will be used. `password`
  defaults to `$PGPASS`. `hostname` defaults to `$PGHOST` or `localhost`.
  """
  def parse_url(url) do
    unless String.match? url, ~r/^[^:\/?#\s]+:\/\// do
      raise Ecto.InvalidURLError, url: url, message: "url should start with a scheme, host should start with //"
    end

    info = URI.parse(url)

    unless String.match? info.path, ~r"^/([^/])+$" do
      raise Ecto.InvalidURLError, url: url, message: "path should be a database name"
    end

    if info.userinfo do
      destructure [username, password], String.split(info.userinfo, ":")
    end

    database = String.slice(info.path, 1, String.length(info.path))
    query = URI.decode_query(info.query || "") |> atomize_keys

    opts = [ username: username,
             password: password,
             hostname: info.host,
             database: database,
             port:     info.port ]

    opts = Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
    opts ++ query
  end

  @doc """
  Converts the given binary to underscore format.
  """
  # TODO: Get rid of me
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
    Enum.map dict, fn {k, v} -> {String.to_atom(k), v} end
  end

  defp to_lower_char(char) when char in ?A..?Z, do: char + 32
  defp to_lower_char(char), do: char
end
