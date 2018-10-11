defmodule Custom.Permalink do
  def type, do: :id

  def cast(string) when is_binary(string) do
    case Integer.parse(string) do
      {int, _} -> {:ok, int}
      :error   -> :error
    end
  end

  def cast(integer) when is_integer(integer), do: {:ok, integer}
  def cast(_), do: :error

  def load(integer) when is_integer(integer), do: {:ok, integer}
  def dump(integer) when is_integer(integer), do: {:ok, integer}
end
