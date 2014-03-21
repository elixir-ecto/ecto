defmodule Simple.Mixfile do
  use Mix.Project

  def project do
    [ app: :simple,
      version: "0.0.1",
      deps: deps ]
  end

  # Configuration for the OTP application
  def application do
    [ mod: { Simple.App, [] },
      applications: [:postgrex, :ecto] ]
  end

  # Returns the list of dependencies in the format:
  # { :foobar, "0.1", git: "https://github.com/elixir-lang/foobar.git" }
  defp deps do
    [ { :postgrex, github: "ericmj/postgrex" },
      { :ecto, path: "../.."} ]
  end
end
