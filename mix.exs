defmodule Ecto.Mixfile do
  use Mix.Project

  def project do
    [ app: :ecto,
      version: "0.0.1",
      deps: deps(Mix.env),
      env: envs,
      elixir: "~> 0.10.0" ]
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
        { :pgsql, github: "semiocast/pgsql" } ]
  end

  defp envs do
    [ pg: [test_paths: ["integration_test/pg"] ] ]
  end
end
