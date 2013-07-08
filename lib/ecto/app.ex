defmodule Ecto.App do
  @moduledoc false

  use Application.Behaviour

  def start(_type, _args) do
    Ecto.Sup.start_link
  end
end
