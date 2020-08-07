defmodule Ecto.MixProject do
  use Mix.Project

  @version "3.4.6"

  def project do
    [
      app: :ecto,
      version: @version,
      elixir: "~> 1.7",
      deps: deps(),
      consolidate_protocols: Mix.env() != :test,

      # Hex
      description: "A toolkit for data mapping and language integrated query for Elixir",
      package: package(),

      # Docs
      name: "Ecto",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :eex],
      mod: {Ecto.Application, []}
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 0.4"},
      {:decimal, "~> 1.6 or ~> 2.0"},
      {:jason, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.20", only: :docs}
    ]
  end

  defp package do
    [
      maintainers: ["Eric Meadows-Jönsson", "José Valim", "James Fish", "Michał Muskała"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/elixir-ecto/ecto"},
      files:
        ~w(.formatter.exs mix.exs README.md CHANGELOG.md lib) ++
          ~w(integration_test/cases integration_test/support)
    ]
  end

  defp docs do
    [
      main: "Ecto",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/ecto",
      logo: "guides/images/e.png",
      extra_section: "GUIDES",
      source_url: "https://github.com/elixir-ecto/ecto",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: [
        # Ecto,
        # Ecto.Changeset,
        # Ecto.Multi,
        # Ecto.Query,
        # Ecto.Repo,
        # Ecto.Schema,
        # Ecto.Schema.Metadata,
        # Ecto.Type,
        # Ecto.UUID,
        # Mix.Ecto,

        "Query APIs": [
          Ecto.Query.API,
          Ecto.Query.WindowAPI,
          Ecto.Queryable,
          Ecto.SubQuery
        ],
        "Adapter specification": [
          Ecto.Adapter,
          Ecto.Adapter.Queryable,
          Ecto.Adapter.Schema,
          Ecto.Adapter.Storage,
          Ecto.Adapter.Transaction
        ],
        "Association structs": [
          Ecto.Association.BelongsTo,
          Ecto.Association.Has,
          Ecto.Association.HasThrough,
          Ecto.Association.ManyToMany,
          Ecto.Association.NotLoaded
        ]
      ]
    ]
  end

  def extras() do
    [
      "guides/introduction/Getting Started.md",
      "guides/introduction/Testing with Ecto.md",
      "guides/howtos/Aggregates and subqueries.md",
      "guides/howtos/Composable transactions with Multi.md",
      "guides/howtos/Constraints and Upserts.md",
      "guides/howtos/Data mapping and validation.md",
      "guides/howtos/Dynamic queries.md",
      "guides/howtos/Multi tenancy with query prefixes.md",
      "guides/howtos/Polymorphic associations with many to many.md",
      "guides/howtos/Replicas and dynamic repositories.md",
      "guides/howtos/Schemaless queries.md",
      "guides/howtos/Test factories.md"
    ]
  end

  defp groups_for_extras do
    [
      "Introduction": ~r/guides\/introduction\/.?/,
      "How-To's": ~r/guides\/howtos\/.?/
    ]
  end
end
