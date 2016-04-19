defmodule Simple.Mixfile do
  use Mix.Project

  def project do
    [app: :simple,
     version: "0.0.1",
     deps: deps,
     aliases: aliases]
  end

  def application do
    [mod: {Simple.App, []},
     applications: [:postgrex, :ecto, :logger]]
  end

  defp deps do
    [{:postgrex, ">= 0.0.0"},
     {:ecto, path: "../.."}]
  end

  defp aliases do
    ["ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.setup"],
     "test":       ["ecto.reset", "test"]]
  end
end
