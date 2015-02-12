defmodule Ecto.UUID do
  @moduledoc """
  An Ecto type for UUIDs strings.

  In contrast to the `:uuid` type, `Ecto.UUID` works
  with UUID as strings instead of binary data.
  """

  @behaviour Ecto.Type

  @doc """
  The Ecto primitive type.
  """
  def type, do: :uuid

  @doc """
  UUIDs are blank when given as strings and the string is blank.
  """
  defdelegate blank?(value), to: Ecto.Type

  @doc """
  Casts to UUID.
  """
  def cast(<< _::64, ?-, _::32, ?-, _::32, ?-, _::32, ?-, _::96 >> = u), do: {:ok, u}
  def cast(uuid = << _::128 >>), do: load(uuid)
  def cast(_), do: :error

  @doc """
  Converts an string representing a UUID into a binary.
  """
  def dump(<< u0::64, ?-, u1::32, ?-, u2::32, ?-, u3::32, ?-, u4::96 >>) do
    case Base.decode16(<< u0::64, u1::32, u2::32, u3::32, u4::96 >>, case: :mixed) do
      {:ok, value} -> {:ok, %Ecto.Query.Tagged{type: :uuid, value: value}}
      :error       -> :error
    end
  end
  def dump(_), do: :error

  @doc """
  Converts a binary UUID into a string.
  """
  def load(uuid = << _::128 >>) do
   {:ok, encode(uuid)}
  end
  def load(_), do: :error

  @doc """
  Generates a version 4 (random) UUID.
  """
  def generate do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<u0::48, 4::4, u1::12, 2::2, u2::62>> |> encode
  end

  defp encode(<<u0::32, u1::16, u2::16, u3::16, u4::48>>) do
    hex_pad(u0, 8) <> "-" <> hex_pad(u1, 4) <> "-" <> hex_pad(u2, 4) <>
                      "-" <> hex_pad(u3, 4) <> "-" <> hex_pad(u4, 12)
  end

  defp hex_pad(hex, count) do
    hex = Integer.to_string(hex, 16)
    :binary.copy("0", count - byte_size(hex)) <> hex
  end
end
