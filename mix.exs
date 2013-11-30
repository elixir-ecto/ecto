defmodule Ecto.Mixfile do
  use Mix.Project

  def project do
    [ app: :ecto,
      version: "0.0.1",
      deps: deps(Mix.env),
      env: envs,
      name: "Ecto",
      elixir: "~> 0.11.2-dev",
      source_url: "https://github.com/elixir-lang/ecto",
      docs: fn -> [
        source_ref: System.cmd("git rev-parse --verify --quiet HEAD"),
        main: "overview",
        readme: true ]
      end ]
  end

  def application do
    []
  end

  defp deps(:prod) do
    [ { :poolboy, github: "devinus/poolboy" },
      { :emysql, "0.2", github: "Eonblast/Emysql", ref: "dc2d1d26db0aee512c923e36b798dbfe3b919af9" },
      { :postgrex, "~> 0.2.0", github: "ericmj/postgrex", optional: true } ]
  end

  defp deps(_) do
    deps(:prod) ++
      [ { :ex_doc, github: "elixir-lang/ex_doc" } ]
  end

  defp envs do
    [ pg: [ test_paths: ["integration_test/pg"] ],
      mysql: [test_paths: ["integration_test/mysql"] ],
      all: [ test_paths: ["test", "integration_test/pg", "integartion_test/mysql"] ] ]
  end
end
