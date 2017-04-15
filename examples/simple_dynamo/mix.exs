defmodule SimpleDynamo.Mixfile do
  use Mix.Project

  def project do
    [ app: :simple_dynamo,
      version: "0.0.1",
      dynamos: [SimpleDynamo.Dynamo],
      compilers: [:elixir, :dynamo, :app],
      env: [prod: [compile_path: "ebin"]],
      compile_path: "tmp/#{Mix.env}/simple_dynamo/ebin",
      deps: deps ]
  end

  # Configuration for the OTP application
  def application do
    [ applications: [:cowboy, :dynamo],
      mod: { SimpleDynamo, [] } ]
  end

  defp deps do
    [ { :cowboy, github: "extend/cowboy" },
      { :dynamo, "0.1.0-dev", github: "elixir-lang/dynamo" },
      { :postgrex, github: "ericmj/postgrex" },
      { :ecto, path: "../.."} ]
  end
end
