defmodule Ecto.Mixfile do
  use Mix.Project

  def project do
    [ app: :ecto,
      version: "0.1.0-dev",
      elixir: "~> 0.12.4 or ~> 0.13.0-dev",
      env: envs,
      deps: deps(Mix.env),
      build_per_environment: false,

      # Docs
      name: "Ecto",
      docs: &docs/0,
      source_url: "https://github.com/elixir-lang/ecto" ]
  end

  def application do
    [ applications: [:poolboy] ]
  end

  defp deps(:prod) do
    [ { :poolboy, "~> 1.1.0", github: "devinus/poolboy" },
      { :decimal, "~> 0.1.0", github: "ericmj/decimal" },
      { :postgrex, "~> 0.4.0", github: "ericmj/postgrex", optional: true } ]
  end

  defp deps(_) do
    deps(:prod) ++
      [ { :ex_doc, github: "elixir-lang/ex_doc" } ]
  end

  defp envs do
    [ pg: [ test_paths: ["integration_test/pg"] ],
      all: [ test_paths: ["test", "integration_test/pg"] ] ]
  end

  defp docs do
    [ source_ref: System.cmd("git rev-parse --verify --quiet HEAD"),
      main: "overview",
      readme: true ]
  end
end
