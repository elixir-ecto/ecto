defmodule Ecto.Mixfile do
  use Mix.Project

  def project do
    [ app: :ecto,
      version: "0.0.1",
      deps: deps,
      elixir: "~> 0.9.4-dev" ]
  end

  def application do
    [ applications: [ :poolboy, :pgsql ],
      mod: { Ecto.App, [] },
      registered: [ Ecto.Sup, Ecto.PoolSup ] ]
  end

  defp deps do
    [ { :poolboy, github: "devinus/poolboy" },
      { :pgsql, github: "semiocast/pgsql" } ]
  end
end
