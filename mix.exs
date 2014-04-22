defmodule Ecto.Mixfile do
  use Mix.Project

  def project do
    [ app: :ecto,
      version: "0.1.0-dev",
      elixir: "~> 0.13.1-dev",
      env: envs,
      deps: deps,
      build_per_environment: false,

      # Docs
      name: "Ecto",
      docs: &docs/0,
      source_url: "https://github.com/elixir-lang/ecto" ]
  end

  def application do
    [ applications: [:poolboy] ]
  end

  defp deps() do
    [ { :poolboy, "~> 1.1.0", github: "devinus/poolboy" },
      { :decimal, "~> 0.1.2", github: "ericmj/decimal", override: true },
      { :postgrex, "~> 0.4.2", github: "ericmj/postgrex", optional: true },
      { :ex_doc, github: "elixir-lang/ex_doc", only: :dev } ]
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
