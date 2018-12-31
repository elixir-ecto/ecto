defmodule Ecto.MixProject do
  use Mix.Project

  @version "3.0.6"

  def project do
    [
      app: :ecto,
      version: @version,
      elixir: "~> 1.4",
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
      extra_applications: [:logger, :crypto],
      mod: {Ecto.Application, []}
    ]
  end

  defp deps do
    [
      {:decimal, "~> 1.6"},

      # Optional
      {:poison, "~> 2.2 or ~> 3.0", optional: true},
      {:jason, "~> 1.0", optional: true},

      # Docs
      {:ex_doc, "~> 0.19", only: :docs}
    ]
  end

  defp package do
    [
      maintainers: ["Eric Meadows-Jönsson", "José Valim", "James Fish", "Michał Muskała"],
      licenses: ["Apache 2.0"],
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
      source_url: "https://github.com/elixir-ecto/ecto",
      extras: [
        "guides/Getting Started.md",
        "guides/Testing with Ecto.md"
      ],
      groups_for_modules: [
        # Ecto,
        # Ecto.Changeset,
        # Ecto.LogEntry,
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
end
