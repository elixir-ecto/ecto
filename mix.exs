defmodule Ecto.MixProject do
  use Mix.Project

  @source_url "https://github.com/elixir-ecto/ecto"
  @version "3.12.4"

  def project do
    [
      app: :ecto,
      version: @version,
      elixir: "~> 1.11",
      deps: deps(),
      consolidate_protocols: Mix.env() != :test,
      elixirc_paths: elixirc_paths(Mix.env()),

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
      {:telemetry, "~> 0.4 or ~> 1.0"},
      {:decimal, "~> 2.0"},
      {:jason, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.20", only: :docs}
    ]
  end

  defp package do
    [
      maintainers: ["Eric Meadows-Jönsson", "José Valim", "Felipe Stival", "Greg Rychlewski"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files:
        ~w(.formatter.exs mix.exs README.md CHANGELOG.md lib) ++
          ~w(integration_test/cases integration_test/support)
    ]
  end

  defp docs do
    [
      main: "Ecto",
      source_ref: "v#{@version}",
      logo: "guides/images/e.png",
      extra_section: "GUIDES",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_docs: [
        group_for_function("Query API"),
        group_for_function("Schema API"),
        group_for_function("Transaction API"),
        group_for_function("Process API"),
        group_for_function("Config API"),
        group_for_function("User callbacks")
      ],
      groups_for_modules: [
        # Ecto,
        # Ecto.Changeset,
        # Ecto.Multi,
        # Ecto.Query,
        # Ecto.Repo,
        # Ecto.Schema,
        # Ecto.Schema.Metadata,
        # Mix.Ecto,

        Types: [
          Ecto.Enum,
          Ecto.ParameterizedType,
          Ecto.Type,
          Ecto.UUID
        ],
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
        "Relation structs": [
          Ecto.Association.BelongsTo,
          Ecto.Association.Has,
          Ecto.Association.HasThrough,
          Ecto.Association.ManyToMany,
          Ecto.Association.NotLoaded,
          Ecto.Embedded
        ]
      ],
      before_closing_body_tag: fn
        :html ->
          """
          <script src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
          <script>
            document.addEventListener("DOMContentLoaded", function () {
              mermaid.initialize({
                startOnLoad: false,
                theme: document.body.className.includes("dark") ? "dark" : "default"
              });
              let id = 0;
              for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
                const preEl = codeEl.parentElement;
                const graphDefinition = codeEl.textContent;
                const graphEl = document.createElement("div");
                const graphId = "mermaid-graph-" + id++;
                mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
                  graphEl.innerHTML = svg;
                  bindFunctions?.(graphEl);
                  preEl.insertAdjacentElement("afterend", graphEl);
                  preEl.remove();
                });
              }
            });
          </script>
          """

        _ ->
          ""
      end
    ]
  end

  def extras() do
    [
      "guides/introduction/Getting Started.md",
      "guides/introduction/Embedded Schemas.md",
      "guides/introduction/Testing with Ecto.md",
      "guides/howtos/Aggregates and subqueries.md",
      "guides/howtos/Composable transactions with Multi.md",
      "guides/howtos/Constraints and Upserts.md",
      "guides/howtos/Data mapping and validation.md",
      "guides/howtos/Dynamic queries.md",
      "guides/howtos/Multi tenancy with query prefixes.md",
      "guides/howtos/Multi tenancy with foreign keys.md",
      "guides/howtos/Self-referencing many to many.md",
      "guides/howtos/Polymorphic associations with many to many.md",
      "guides/howtos/Replicas and dynamic repositories.md",
      "guides/howtos/Schemaless queries.md",
      "guides/howtos/Test factories.md",
      "guides/cheatsheets/crud.cheatmd",
      "guides/cheatsheets/associations.cheatmd",
      "CHANGELOG.md"
    ]
  end

  defp group_for_function(group), do: {String.to_atom(group), &(&1[:group] == group)}

  defp groups_for_extras do
    [
      Introduction: ~r/guides\/introduction\/.?/,
      Cheatsheets: ~r/cheatsheets\/.?/,
      "How-To's": ~r/guides\/howtos\/.?/
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
