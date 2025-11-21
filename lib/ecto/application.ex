defmodule Ecto.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    :ok = :persistent_term.put({Ecto.UUID, :millisecond}, :atomics.new(1, signed: false))
    :ok = :persistent_term.put({Ecto.UUID, :nanosecond}, :atomics.new(1, signed: false))

    children = [
      Ecto.Repo.Registry
    ]

    opts = [strategy: :one_for_one, name: Ecto.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
