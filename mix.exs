defmodule Ecto.Mixfile do
  use Mix.Project

  @version "2.2.12"
  @adapters [:pg, :mysql]

  def project do
    [app: :ecto,
     version: @version,
     elixir: "~> 1.4",
     deps: deps(),
     build_per_environment: false,
     consolidate_protocols: false,
     test_paths: test_paths(Mix.env),
     xref: [exclude: [Mariaex, Ecto.Adapters.MySQL.Connection,
                      Postgrex, Ecto.Adapters.Postgres.Connection,
                      DBConnection, DBConnection.Ownership]],

     # Custom testing
     aliases: ["test.all": ["test", "test.adapters"],
               "test.adapters": &test_adapters/1],
     preferred_cli_env: ["test.all": :test],

     # Hex
     description: "A database wrapper and language integrated query for Elixir",
     package: package(),

     # Docs
     name: "Ecto",
     docs: docs()]
  end

  def application do
    [applications: [:logger, :decimal, :poolboy, :crypto],
     env: [json_library: Poison, postgres_map_type: "jsonb"], mod: {Ecto.Application, []}]
  end

  defp deps do
    [
      {:poolboy, "~> 1.5"},
      {:decimal, "~> 1.2"},

      # Drivers
      {:db_connection, "~> 1.1", optional: true},
      {:postgrex, "~> 0.13.0", optional: true},
      {:mariaex, "~> 0.8.0", optional: true},

      # Optional
      {:sbroker, "~> 1.0", optional: true},
      {:poison, "~> 2.2 or ~> 3.0", optional: true},

      # Docs
      {:ex_doc, "~> 0.17", only: :docs},
      {:inch_ex, ">= 0.0.0", only: :docs}
    ]
  end

  defp test_paths(adapter) when adapter in @adapters, do: ["integration_test/#{adapter}"]
  defp test_paths(_), do: ["test/ecto", "test/mix"]

  defp package do
    [
      maintainers: ["Eric Meadows-Jönsson", "José Valim", "James Fish", "Michał Muskała"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/elixir-ecto/ecto"},
      files: ~w(.formatter.exs mix.exs README.md CHANGELOG.md lib) ++
             ~w(integration_test/cases integration_test/sql integration_test/support)
    ]
  end

  defp test_adapters(args) do
    for env <- @adapters, do: env_run(env, args)
  end

  defp env_run(env, args) do
    args = if IO.ANSI.enabled?, do: ["--color"|args], else: ["--no-color"|args]

    IO.puts "==> Running tests for MIX_ENV=#{env} mix test"
    {_, res} = System.cmd "mix", ["test"|args],
                          into: IO.binstream(:stdio, :line),
                          env: [{"MIX_ENV", to_string(env)}]

    if res > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
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
        "guides/Associations.md",
        "guides/Testing with Ecto.md",
      ],
      groups_for_modules: [
        # Ecto,
        # Ecto.Changeset,
        # Ecto.Migration,
        # Ecto.Migrator,
        # Ecto.Multi,
        # Ecto.Schema,
        # Ecto.Schema.Metadata,

        "Repo and Queries": [
          Ecto.LogEntry,
          Ecto.Repo,
          Ecto.Query,
          Ecto.Query.API,
          Ecto.Queryable,
          Ecto.SubQuery
        ],

        "Types": [
          Ecto.DataType,
          Ecto.Date,
          Ecto.DateTime,
          Ecto.Time,
          Ecto.Type,
          Ecto.UUID,
        ],

        "Adapters": [
          Ecto.Adapters.MySQL,
          Ecto.Adapters.Postgres,
          Ecto.Adapters.SQL,
          Ecto.Adapters.SQL.Connection,
          Ecto.Adapters.SQL.Sandbox,
        ],

        "Adapter specification": [
          Ecto.Adapter,
          Ecto.Adapter.Migration,
          Ecto.Adapter.Storage,
          Ecto.Adapter.Structure,
          Ecto.Adapter.Transaction,
        ],

        "Association structs": [
          Ecto.Association.BelongsTo,
          Ecto.Association.Has,
          Ecto.Association.HasThrough,
          Ecto.Association.ManyToMany,
          Ecto.Association.NotLoaded,
        ],

        "Migration structs": [
          Ecto.Migration.Command,
          Ecto.Migration.Constraint,
          Ecto.Migration.Index,
          Ecto.Migration.Reference,
          Ecto.Migration.Table,
        ]
      ]
    ]
  end
end
