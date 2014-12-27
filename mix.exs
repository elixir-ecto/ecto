defmodule Ecto.Mixfile do
  use Mix.Project

  @version "0.3.0"

  def project do
    [app: :ecto,
     version: @version,
     elixir: "~> 1.0",
     deps: deps,
     build_per_environment: false,
     test_paths: test_paths(Mix.env),

     # Hex
     description: description,
     package: package,

     # Docs
     name: "Ecto",
     docs: [main: "overview", source_ref: "v#{@version}",
            source_url: "https://github.com/elixir-lang/ecto"]]
  end

  def application do
    [applications: [:decimal, :poolboy]]
  end

  defp deps do
    [{:poolboy, "~> 1.4.1"},
     {:decimal, "~> 0.2.3"},
     {:postgrex, "~> 0.6.0", optional: true},
     {:ex_doc, "~> 0.6", only: :docs},
     {:earmark, "~> 0.1", only: :docs},
     {:inch_ex, only: :docs}]
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
     links: %{"GitHub" => "https://github.com/elixir-lang/ecto"}]
  end
end
