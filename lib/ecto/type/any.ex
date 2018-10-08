defmodule Ecto.Type.Any do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :any

  def cast(term), do: {:ok, term}

  def dump(term), do: {:ok, term}

  def load(term), do: {:ok, term}

  def equal?(a, b), do: a == b
end
