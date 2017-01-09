defmodule Friends.Mixfile do
  use Mix.Project

  def project do
    [app: :friends,
     version: "0.1.0",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     aliases: aliases()]
  end

  def application do
    [applications: [:logger, :ecto, :postgrex],
     mod: {Friends, []}]
  end

  defp aliases do
    [test: ["ecto.create", "ecto.migrate", "test"]]
  end

  defp deps do
    # Normally you would specify a version of Ecto, like this:
    #
    # {:ecto, "~> 2.0"}
    #
    # It is not done in this instance because we want to refer to the local Ecto.
    [{:ecto, path: "../.."},
     {:postgrex, ">= 0.0.0-rc"}]
  end
end
