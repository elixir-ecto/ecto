defmodule CustomPermalink do
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

defmodule PrefixedString do
  use Ecto.Type
  def type(), do: :string
  def cast(string), do: {:ok, string}
  def load(string), do: {:ok, "PREFIX-" <> string}
  def dump("PREFIX-" <> string), do: {:ok, string}
  def dump(_string), do: :error
  def embed_as(_), do: :dump
end

defmodule WrappedInteger do
  use Ecto.Type
  def type(), do: :integer
  def cast(integer), do: {:ok, {:int, integer}}
  def load(integer), do: {:ok, {:int, integer}}
  def dump({:int, integer}), do: {:ok, integer}
end

defmodule ParameterizedPrefixedString do
  use Ecto.ParameterizedType
  def init(opts), do: Enum.into(opts, %{})
  def type(_), do: :string

  def cast(data, %{prefix: prefix}) do
    if String.starts_with?(data, [prefix <> "-"]) do
      {:ok, data}
    else
      {:ok, prefix <> "-" <> data}
    end
  end

  def load(string, _, %{prefix: prefix}), do: {:ok, prefix <> "-" <> string}
  def dump(data, _, %{prefix: _prefix}), do: {:ok, data |> String.split("-") |> List.last()}
  def embed_as(_, _), do: :dump
end
