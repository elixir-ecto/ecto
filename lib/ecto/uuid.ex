defmodule Ecto.UUID do
  @moduledoc """
  An Ecto type for UUIDs strings.
  """

  @behaviour Ecto.Type

  @doc """
  The Ecto type.
  """
  def type, do: :uuid

  @doc """
  Casts to UUID.
  """
  def cast(<< _::64, ?-, _::32, ?-, _::32, ?-, _::32, ?-, _::96 >> = u), do: {:ok, u}
  def cast(_), do: :error

  @doc """
  Converts a string representing a UUID into a binary.
  """
  def dump(<< a1, a2, a3, a4, a5, a6, a7, a8, ?-,
              b1, b2, b3, b4, ?-,
              c1, c2, c3, c4, ?-,
              d1, d2, d3, d4, ?-,
              e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12 >>) do
    try do
      << d(a1)::4, d(a2)::4, d(a3)::4, d(a4)::4,
         d(a5)::4, d(a6)::4, d(a7)::4, d(a8)::4,
         d(b1)::4, d(b2)::4, d(b3)::4, d(b4)::4,
         d(c1)::4, d(c2)::4, d(c3)::4, d(c4)::4,
         d(d1)::4, d(d2)::4, d(d3)::4, d(d4)::4,
         d(e1)::4, d(e2)::4, d(e3)::4, d(e4)::4,
         d(e5)::4, d(e6)::4, d(e7)::4, d(e8)::4,
         d(e9)::4, d(e10)::4, d(e11)::4, d(e12)::4 >>
    catch
      :error -> :error
    else
      binary ->
        {:ok, %Ecto.Query.Tagged{type: :uuid, value: binary}}
    end
  end
  def dump(_), do: :error

  @compile {:inline, d: 1}

  defp d(?0), do: 0
  defp d(?1), do: 1
  defp d(?2), do: 2
  defp d(?3), do: 3
  defp d(?4), do: 4
  defp d(?5), do: 5
  defp d(?6), do: 6
  defp d(?7), do: 7
  defp d(?8), do: 8
  defp d(?9), do: 9
  defp d(?A), do: 10
  defp d(?B), do: 11
  defp d(?C), do: 12
  defp d(?D), do: 13
  defp d(?E), do: 14
  defp d(?F), do: 15
  defp d(?a), do: 10
  defp d(?b), do: 11
  defp d(?c), do: 12
  defp d(?d), do: 13
  defp d(?e), do: 14
  defp d(?f), do: 15
  defp d(_),  do: throw(:error)

  @doc """
  Converts a binary UUID into a string.
  """
  def load(<<_::128>> = uuid) do
   {:ok, encode(uuid)}
  end
  def load(<<_::64, ?-, _::32, ?-, _::32, ?-, _::32, ?-, _::96>> = string) do
    raise "trying to load string UUID as Ecto.UUID: #{inspect string}. " <>
          "Maybe you wanted to declare :uuid as your database field?"
  end
  def load(%Ecto.Query.Tagged{type: :uuid, value: uuid}) do
    {:ok, encode(uuid)}
  end
  def load(_), do: :error

  @doc """
  Generates a version 4 (random) UUID.
  """
  def generate do
    bingenerate() |> encode
  end

  @doc """
  Generates a version 4 (random) UUID in the binary format.
  """
  def bingenerate do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<u0::48, 4::4, u1::12, 2::2, u2::62>>
  end

  # Callback invoked by autogenerate in schema.
  @doc false
  def autogenerate do
    %Ecto.Query.Tagged{type: :uuid, value: bingenerate()}
  end

  defp encode(<<u0::32, u1::16, u2::16, u3::16, u4::48>>) do
    hex_pad(u0, 8) <> "-" <>
    hex_pad(u1, 4) <> "-" <>
    hex_pad(u2, 4) <> "-" <>
    hex_pad(u3, 4) <> "-" <>
    hex_pad(u4, 12)
  end

  defp hex_pad(hex, count) do
    hex = Integer.to_string(hex, 16)
    lower(hex, :binary.copy("0", count - byte_size(hex)))
  end

  defp lower(<<h, t::binary>>, acc) when h in ?A..?F,
    do: lower(t, acc <> <<h + 32>>)
  defp lower(<<h, t::binary>>, acc),
    do: lower(t, acc <> <<h>>)
  defp lower(<<>>, acc),
    do: acc
end
