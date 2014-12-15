defmodule Ecto.MockRepo do
  use Ecto.Repo, adapter: Ecto.MockAdapter

  def conf, do: []
  def priv, do: app_dir(:ecto, "priv/db")
  def url,  do: parse_url("ecto://user@localhost/db")
end
