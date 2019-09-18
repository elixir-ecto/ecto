defmodule Ecto.UUID do
  @moduledoc """
  An Ecto type for UUIDs strings.
  """

  use Ecto.Type

  @typedoc """
  A hex-encoded UUID string.
  """
  @type t :: <<_::288>>

  @typedoc """
  A raw binary representation of a UUID.
  """
  @type raw :: <<_::128>>

  @doc false
  def type, do: :uuid

  @doc """
  Casts to UUID.
  """
  @spec cast(t | raw | any) :: {:ok, t} | :error
  def cast(<< a1, a2, a3, a4, a5, a6, a7, a8, ?-,
              b1, b2, b3, b4, ?-,
              c1, c2, c3, c4, ?-,
              d1, d2, d3, d4, ?-,
              e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12 >>) do
    << c(a1), c(a2), c(a3), c(a4),
       c(a5), c(a6), c(a7), c(a8), ?-,
       c(b1), c(b2), c(b3), c(b4), ?-,
       c(c1), c(c2), c(c3), c(c4), ?-,
       c(d1), c(d2), c(d3), c(d4), ?-,
       c(e1), c(e2), c(e3), c(e4),
       c(e5), c(e6), c(e7), c(e8),
       c(e9), c(e10), c(e11), c(e12) >>
  catch
    :error -> :error
  else
    casted -> {:ok, casted}
  end
  def cast(<< _::128 >> = binary), do: encode(binary)
  def cast(_), do: :error

  @doc """
  Same as `cast/1` but raises `Ecto.CastError` on invalid arguments.
  """
  @spec cast!(t | raw | any) :: t
  def cast!(value) do
    case cast(value) do
      {:ok, uuid} -> uuid
      :error -> raise Ecto.CastError, type: __MODULE__, value: value
    end
  end

  @compile {:inline, c: 1}

  defp c(?0), do: ?0
  defp c(?1), do: ?1
  defp c(?2), do: ?2
  defp c(?3), do: ?3
  defp c(?4), do: ?4
  defp c(?5), do: ?5
  defp c(?6), do: ?6
  defp c(?7), do: ?7
  defp c(?8), do: ?8
  defp c(?9), do: ?9
  defp c(?A), do: ?a
  defp c(?B), do: ?b
  defp c(?C), do: ?c
  defp c(?D), do: ?d
  defp c(?E), do: ?e
  defp c(?F), do: ?f
  defp c(?a), do: ?a
  defp c(?b), do: ?b
  defp c(?c), do: ?c
  defp c(?d), do: ?d
  defp c(?e), do: ?e
  defp c(?f), do: ?f
  defp c(_),  do: throw(:error)

  @doc """
  Converts a string representing a UUID into a binary.
  """
  @spec dump(t | any) :: {:ok, raw} | :error
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
        {:ok, binary}
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
  @spec load(raw | any) :: {:ok, t} | :error
  def load(<<_::128>> = uuid) do
    encode(uuid)
  end
  def load(<<_::64, ?-, _::32, ?-, _::32, ?-, _::32, ?-, _::96>> = string) do
    raise ArgumentError, "trying to load string UUID as Ecto.UUID: #{inspect string}. " <>
                         "Maybe you wanted to declare :uuid as your database field?"
  end
  def load(_), do: :error

  @doc """
  Generates a version 4 (random) UUID.
  """
  @spec generate() :: t
  def generate() do
    {:ok, uuid} = encode(bingenerate())
    uuid
  end

  @doc """
  Generates a version 4 (random) UUID in the binary format.
  """
  @spec bingenerate() :: raw
  def bingenerate() do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<u0::48, 4::4, u1::12, 2::2, u2::62>>
  end

  # Callback invoked by autogenerate fields.
  @doc false
  def autogenerate, do: generate()

  defp encode(<< a1::4, a2::4, a3::4, a4::4,
                 a5::4, a6::4, a7::4, a8::4,
                 b1::4, b2::4, b3::4, b4::4,
                 c1::4, c2::4, c3::4, c4::4,
                 d1::4, d2::4, d3::4, d4::4,
                 e1::4, e2::4, e3::4, e4::4,
                 e5::4, e6::4, e7::4, e8::4,
                 e9::4, e10::4, e11::4, e12::4 >>) do
    << e(a1), e(a2), e(a3), e(a4), e(a5), e(a6), e(a7), e(a8), ?-,
       e(b1), e(b2), e(b3), e(b4), ?-,
       e(c1), e(c2), e(c3), e(c4), ?-,
       e(d1), e(d2), e(d3), e(d4), ?-,
       e(e1), e(e2), e(e3), e(e4), e(e5), e(e6), e(e7), e(e8), e(e9), e(e10), e(e11), e(e12) >>
  catch
    :error -> :error
  else
    encoded -> {:ok, encoded}
  end

  @compile {:inline, e: 1}

  defp e(0),  do: ?0
  defp e(1),  do: ?1
  defp e(2),  do: ?2
  defp e(3),  do: ?3
  defp e(4),  do: ?4
  defp e(5),  do: ?5
  defp e(6),  do: ?6
  defp e(7),  do: ?7
  defp e(8),  do: ?8
  defp e(9),  do: ?9
  defp e(10), do: ?a
  defp e(11), do: ?b
  defp e(12), do: ?c
  defp e(13), do: ?d
  defp e(14), do: ?e
  defp e(15), do: ?f
end
