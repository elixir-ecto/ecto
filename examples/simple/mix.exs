defmodule Simple.Mixfile do
  use Mix.Project

  def project do
    [app: :simple,
     version: "0.0.1",
     deps: deps]
  end

  def application do
    [mod: {Simple.App, []},
     applications: [:postgrex, :ecto]]
  end

  defp deps do
    [{:postgrex, ">= 0.0.0"},
     {:ecto, path: "../.."}]
  end
end
