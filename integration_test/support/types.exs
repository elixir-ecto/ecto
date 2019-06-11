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

defmodule Custom.Composite do
  def type, do: :any

  def cast(nil), do: {:ok, :none}
  def cast(value), do: {:ok, {:some, value}}

  def load(nil), do: {:ok, :none}
  def load(value), do: {:ok, {:some, value}}
  def dump({:some, value}), do: {:ok, value}
  def dump(:none), do: {:ok, nil}
end
