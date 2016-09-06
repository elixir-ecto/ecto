defmodule Friends.Mixfile do
  use Mix.Project

  def project do
    [app: :friends,
     version: "0.1.0",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     aliases: aliases()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger, :postgrex],
     mod: {Friends, []}]
  end

  defp aliases do
    [test: ["ecto.create", "ecto.migrate", "test"]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    # Normally you would specify a version of Ecto, like this:
    #
    # {:ecto, "~> 2.0"}
    #
    # It is not done in this instance because we want to refer to the local Ecto.
    [{:ecto, path: "../.."},
     {:postgrex, "~> 0.11"}]
  end
end
