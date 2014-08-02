defmodule Ecto.Mixfile do
  use Mix.Project

  def project do
    [app: :ecto,
     version: "0.2.3-dev",
     elixir: "~> 0.15.0",
     deps: deps,
     build_per_environment: false,
     test_paths: test_paths(Mix.env),

     description: description,
     package: package,

     # Docs
     name: "Ecto",
     docs: &docs/0,
     source_url: "https://github.com/elixir-lang/ecto"]
  end

  def application do
    [applications: [:decimal, :poolboy]]
  end

  defp deps do
    [{:poolboy, "~> 1.2.1"},
     # {:decimal, github: "ericmj/decimal", optional: true},
     # {:postgrex, github: "ericmj/postgrex", optional: true},
     {:decimal, "~> 0.2.3", optional: true},
     {:postgrex, "~> 0.5.3", optional: true},
     {:ex_doc, "~> 0.5", only: :dev},
     {:earmark, "~> 0.1", only: :dev}]
  end

  defp test_paths(:pg),  do: ["integration_test/pg"]
  defp test_paths(:all), do: ["test", "integration_test/pg"]
  defp test_paths(_),    do: ["test"]

  defp description do
    """
    Ecto is a domain specific language for writing queries and interacting with databases in Elixir.
    """
  end

  defp package do
    [contributors: ["Eric Meadows-Jönsson", "José Valim"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/elixir-lang/ecto",
              "Docs" => "http://elixir-lang.org/docs/ecto/"}]
  end

  defp docs do
    {ref, 0} = System.cmd("git", ["rev-parse", "--verify", "--quiet", "HEAD"])
    [source_ref: ref,
     main: "overview",
     readme: true]
  end
end
