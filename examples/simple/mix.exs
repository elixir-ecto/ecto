defmodule Simple.Mixfile do
  use Mix.Project

  def project do
    [ app: :simple,
      version: "0.0.1",
      elixir: "~> 0.9.4-dev",
      deps: deps ]
  end

  # Configuration for the OTP application
  def application do
    [ mod: { Simple.App, [] } ]
  end

  # Returns the list of dependencies in the format:
  # { :foobar, "0.1", git: "https://github.com/elixir-lang/foobar.git" }
  defp deps do
    [ { :ecto, path: "../.."},
      { :pgsql, github: "semiocast/pgsql" }]
  end
end
