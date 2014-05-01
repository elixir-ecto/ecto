defmodule Ecto.Mixfile do
  use Mix.Project

  def project do
    [app: :ecto,
     version: "0.1.0-dev",
     elixir: "~> 0.13.1",
     deps: deps,
     build_per_environment: false,
     test_paths: test_paths(Mix.env),

     # Docs
     name: "Ecto",
     docs: &docs/0,
     source_url: "https://github.com/elixir-lang/ecto"]
  end

  def application do
    [applications: [:decimal, :poolboy]]
  end

  defp deps do
    [ { :poolboy, "~> 1.2.1" },
      { :decimal, "~> 0.2.0" },
      { :postgrex, "~> 0.5.0", optional: true },
      { :ex_doc, github: "elixir-lang/ex_doc", only: :dev } ]
  end

  defp test_paths(:pg),  do: ["integration_test/pg"]
  defp test_paths(:all), do: ["test", "integration_test/pg"]
  defp test_paths(_),    do: ["test"]

  defp docs do
    [source_ref: System.cmd("git rev-parse --verify --quiet HEAD"),
     main: "overview",
     readme: true]
  end
end
