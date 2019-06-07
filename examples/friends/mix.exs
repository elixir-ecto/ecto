defmodule Friends.Mixfile do
  use Mix.Project

  def project do
    [
      app: :friends,
      version: "0.1.0",
      elixir: "~> 1.4",
      build_embedded: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Friends.Application, []}
    ]
  end

  defp aliases do
    [
      test: ["ecto.create", "ecto.migrate", "test"]
    ]
  end

  defp deps do
    # Normally you would specify a version of Ecto, like this:
    #
    # {:ecto, "~> 3.0"}
    #
    # It is not done in this instance because we want to refer to the local Ecto.
    [
      {:ecto, path: "../..", override: true},
      {:postgrex, ">= 0.0.0"},
      {:ecto_sql, "~> 3.0"},
      {:jason, "~> 1.0"}
    ]
  end
end
