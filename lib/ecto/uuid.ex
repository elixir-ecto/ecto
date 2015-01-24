defmodule Ecto.UUID do
  @moduledoc """
  An Ecto type for UUIDs.
  """

  @behaviour Ecto.Type

  @doc """
  The Ecto primitive type.
  """
  def type, do: :uuid

  @doc """
  UUIDs are never blank.
  """
  def blank?(_), do: false

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
    Base.decode16(<< u0::64, u1::32, u2::32, u3::32, u4::96 >>, case: :mixed)
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
  Generates a version 4 (random) UUID
  """
  def generate do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<u0::48, 4::4, u1::12, 2::2, u2::62>> |> encode
  end

  defp encode(<<u0::32, u1::16, u2::16, u3::16, u4::48>>) do
    :io_lib.format("~8.16.0B-~4.16.0B-~4.16.0B-~4.16.0B-~12.16.0B", [u0, u1, u2, u3, u4]) |> to_string
  end
end