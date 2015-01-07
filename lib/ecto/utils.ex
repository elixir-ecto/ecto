defmodule Ecto.Utils do
  @doc """
  Parses an Ecto URL of the following format:
  `ecto://username:password@hostname:port/database?opts=123`, %{} where all options
  but the database is optional.

  Second parameters is for database options:
    %{template: ~s(template0),
      encoding: ~s(UTF8),
      lc_collate: ~s(en_US.UTF-8),
      lc_ctype: ~s(en_US.UTF-8)
    }


  If `username` is not specified, `$PGUSER` or `$USER` will be used. `password`
  defaults to `$PGPASS`. `hostname` defaults to `$PGHOST` or `localhost`.
  """
  def parse_url(url, db_opt\\ %{}) do
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
    opts ++ query ++ db_opts_mearge(db_opt)
  end

  def db_opts_mearge(opt\\ %{}) do
    %{template: ~s(template0),
      encoding: ~s(UTF8),
      lc_collate: ~s(en_US.UTF-8),
      lc_ctype: ~s(en_US.UTF-8)
    } |> Map.merge(opt) |> Map.to_list
  end

  defp atomize_keys(dict) do
    Enum.map dict, fn {k, v} -> {String.to_atom(k), v} end
  end
end
