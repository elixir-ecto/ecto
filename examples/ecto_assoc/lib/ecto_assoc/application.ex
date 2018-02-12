defmodule EctoAssoc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      EctoAssoc.Repo
      # Starts a worker by calling: EctoAssoc.Worker.start_link(arg)
      # {EctoAssoc.Worker, arg},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EctoAssoc.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
