defmodule Ecto.Mixfile do
  use Mix.Project

  def project do
    [ app: :ecto,
      version: "0.0.1",
      deps: deps(Mix.env),
      env: envs,
      elixir: "~> 0.10.2" ]
  end

  def application do
    [ ]
  end

  defp deps(:prod) do
    [ { :poolboy, github: "devinus/poolboy" } ]
  end

  defp deps(_) do
    deps(:prod) ++
      [ { :ex_doc, github: "elixir-lang/ex_doc" },
        { :pgsql, github: "ericmj/pgsql", branch: "elixir" } ]
  end

  defp envs do
    [ pg: [ test_paths: ["integration_test/pg"] ],
      all: [ test_paths: ["test", "integration_test/pg"] ] ]
  end
end
