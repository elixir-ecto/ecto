defmodule Ecto.Mixfile do
  use Mix.Project

  @version "1.0.1"
  @adapters [:pg, :mysql]
  @pools [:poolboy, :sojourn_timeout, :sojourn_codel]

  def project do
    [app: :ecto,
     version: @version,
     elixir: "~> 1.0",
     deps: deps,
     build_per_environment: false,
     test_paths: test_paths(Mix.env),

     # Custom testing
     aliases: ["test.all": ["test", "test.pools", "test.adapters"],
               "test.pools": &test_pools/1,
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
     env: [json_library: Poison]]
  end

  defp deps do
    [{:poolboy, "~> 1.4"},
     {:sbroker, "~> 0.7", optional: true},
     {:decimal, "~> 1.0"},
     {:postgrex, "~> 0.9.1", optional: true},
     {:mariaex, "~> 0.4.1", optional: true},
     {:poison, "~> 1.0", optional: true},
     {:ex_doc, "~> 0.7", only: :docs},
     {:earmark, "~> 0.1", only: :docs},
     {:inch_ex, only: :docs}]
  end

  defp test_paths(adapter) when adapter in @adapters, do: ["integration_test/#{adapter}"]
  defp test_paths(pool) when pool in @pools, do: ["test/pool/#{pool(pool)}"]
  defp test_paths(_), do: ["test/ecto", "test/mix"]

  defp pool(:sojourn_timeout), do: "sojourn_broker"
  defp pool(:sojourn_codel),   do: "sojourn_broker"
  defp pool(:poolboy),         do: "poolboy"

  defp description do
    """
    Ecto is a domain specific language for writing queries and interacting with databases in Elixir.
    """
  end

  defp package do
    [contributors: ["Eric Meadows-Jönsson", "José Valim"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/elixir-lang/ecto"},
     files: ~w(mix.exs README.md CHANGELOG.md lib) ++
            ~w(integration_test/cases integration_test/sql integration_test/support)]
  end

  defp test_pools(args) do
    for env <- @pools, do: env_run(env, args)
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
