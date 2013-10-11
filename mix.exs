defmodule Ecto.Mixfile do
  use Mix.Project

  def project do
    [ app: :ecto,
      version: "0.0.1",
      deps: deps(Mix.env),
      env: envs,
      name: "Ecto",
      elixir: "~> 0.10.4-dev",
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

defmodule Mix.Tasks.Release_docs do
  @shortdoc "Releases docs"

  def run(_) do
    Mix.Task.run "docs"

    File.rm_rf "../elixir-lang.github.com/docs/ecto"
    File.cp_r "docs/.", "../elixir-lang.github.com/docs/ecto/"
    File.rm_rf "docs"
  end
end
