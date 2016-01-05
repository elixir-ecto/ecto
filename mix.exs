defmodule Ecto.Mixfile do
  use Mix.Project

  @version "2.0.0-dev"
  @adapters [:pg]

  def project do
    [app: :ecto,
     version: @version,
     elixir: "~> 1.2-rc",
     deps: deps,
     build_per_environment: false,
     consolidate_protocols: false,
     test_paths: test_paths(Mix.env),

     # Custom testing
     aliases: ["test.all": ["test", "test.adapters"],
               "test.adapters": &test_adapters/1],
     preferred_cli_env: ["test.all": :test],

     # Hex
     description: description,
     package: package,

     # Docs
     name: "Ecto",
     docs: [source_ref: "v#{@version}", main: "Ecto",
            source_url: "https://github.com/elixir-lang/ecto"]]
  end

  def application do
    [applications: [:logger, :decimal, :poolboy],
     env: [json_library: Poison], mod: {Ecto.Application, []}]
  end

  defp deps do
    [{:poolboy, "~> 1.5"},
     {:decimal, "~> 1.0"},

     # Drivers
     # {:mariaex, "~> 0.6", optional: true},
     {:postgrex, "~> 0.10", github: "ericmj/postgrex", optional: true},
     {:db_connection, "~> 0.1.7", github: "fishcakez/db_connection", override: true},

     # Optional
     {:sbroker, "~> 0.7", optional: true},
     {:poison, "~> 1.0", optional: true},

     # Docs
     {:ex_doc, "~> 0.10", only: :docs},
     {:earmark, "~> 0.1", only: :docs},
     {:inch_ex, only: :docs}]
  end

  defp test_paths(adapter) when adapter in @adapters, do: ["integration_test/#{adapter}"]
  defp test_paths(_), do: ["test/ecto", "test/mix"]

  defp description do
    """
    Ecto is a domain specific language for writing queries and interacting with databases in Elixir.
    """
  end

  defp package do
    [maintainers: ["Eric Meadows-Jönsson", "José Valim", "James Fish", "Michał Muskała"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/elixir-lang/ecto"},
     files: ~w(mix.exs README.md CHANGELOG.md lib) ++
            ~w(integration_test/cases integration_test/sql integration_test/support)]
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
end
