defmodule Ecto.Mixfile do
  use Mix.Project

  def project do
    [ app: :ecto,
      version: "0.0.1",
      deps: deps(Mix.env),
      elixir: "~> 0.9.4-dev" ]
  end

  def application do
    [ applications: [ :poolboy ],
      mod: { Ecto.App, [] },
      registered: [ Ecto.Sup, Ecto.PoolSup ] ]
  end

  defp deps(:prod) do
    [ { :poolboy, github: "devinus/poolboy" } ]
  end

  defp deps(_) do
    deps(:prod) ++
      [ { :pgsql, github: "semiocast/pgsql" } ]
  end
end
