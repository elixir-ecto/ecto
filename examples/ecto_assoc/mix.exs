defmodule EctoAssoc.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ecto_assoc,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {EctoAssoc.Application, []}
    ]
  end

  defp deps do
    # Normally you would specify a version of Ecto, like this:
    #
    # {:ecto, "~> 2.0"}
    #
    # It is not done in this instance because we want to refer to the local Ecto.
    [
      {:ecto, path: "../.."},
      {:postgrex, ">= 0.0.0", override: true}
    ]
  end
end
