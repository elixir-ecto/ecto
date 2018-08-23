defmodule Ecto.DiscreteRange do
  @moduledoc """
  Define useful functions to create an ecto.type for the postgres
  range type for discrete types. It represents the interval as a
  `closed-open` interval.

  To use this module your type must have a well define successor
  function and a comparison function.
  """

  @typedoc """
  The type of a point in the range.
  """
  @type t :: :infinity | :_infinity | term

  @typedoc """
  The successor function. For example, for integer type, returns,
  `succ_fn(n)` must return `n+1`.
  """
  @type succ_fn :: (t -> t)

  @typedoc """
  The comparison function.
  """
  @type comp_fn :: (t, t -> :lt | :eq | :gt)

  @typedoc """
  Allen's relantionships between intervals. Refer to
  https://en.wikipedia.org/w/index.php?title=Allen%27s_interval_algebra&oldid=846947944 for more information.
  """
  @type allens_relation ::
          :equals | :finishes | :starts | :meets | :before | :after | :during | :overlaps

  @doc """
  Creates a new interval.

    * `:succ_fn` computes the next value;
    * `:comp_fn` comparator for the given type;
    * `:lower` the lower term of the interval;
    * `:upper` the upper term of the interval;
    * `:mode` defines how to interpret interval boundaries;
  """
  @spec new(succ_fn, comp_fn, Ecto.Type, t, t, {:open | :closed, :open | :closed}) ::
          {:ok, {t, t}} | :error
  def new(succ_fn, comp_fn, ecto_ty, lower, upper, mode) do
    interval_fn =
      case mode do
        {:closed, :open} ->
          fn a, b -> {:ok, {a, b}} end

        {:closed, :closed} ->
          fn a, b -> {:ok, {a, succ_term(succ_fn, b)}} end

        {:open, :open} ->
          fn a, b -> {:ok, {succ_term(succ_fn, a), b}} end

        {:open, :closed} ->
          fn a, b -> {:ok, {succ_term(succ_fn, a), succ_term(succ_fn, b)}} end

        _ ->
          fn _a, _b -> :error end
      end

    with {:ok, lower} <- cast_term(:l, ecto_ty, lower),
         {:ok, upper} <- cast_term(:r, ecto_ty, upper),
         {:ok, {lower, upper}} <- interval_fn.(lower, upper),
         true <- :gt != comp_term(comp_fn, lower, upper) do
      {:ok, {lower, upper}}
    else
      _ -> :error
    end
  end

  @spec load(succ_fn, Ecto.Type.t(), %Postgrex.Range{}) :: {:ok, {t, t}} | :error
  def load(succ_fn, ecto_ty, value = %Postgrex.Range{}) do
    with {:ok, lower} <- load_term(:l, ecto_ty, value.lower),
         {:ok, upper} <- load_term(:u, ecto_ty, value.upper) do
      lower =
        if value.lower_inclusive do
          lower
        else
          succ_term(succ_fn, lower)
        end

      upper =
        if value.upper_inclusive do
          succ_term(succ_fn, upper)
        else
          upper
        end

      {:ok, {lower, upper}}
    end
  end

  @spec cast(succ_fn, comp_fn, Ecto.Type.t(), String.t()) :: {:ok, {t, t}} | :error
  def cast(succ_fn, comp_fn, ecto_ty, value) when is_binary(value) do
    with [lower, upper] <- String.split(value, ",", parts: 2),
         {:ok, lmode} <- cast_mode(:l, String.at(lower, 0)),
         {:ok, rmode} <- cast_mode(:u, String.at(upper, -1)),
         {:ok, lower} <- cast_term(:l, ecto_ty, String.slice(lower, 1..-1)),
         {:ok, upper} <- cast_term(:u, ecto_ty, String.slice(upper, 0..-2)) do
      new(succ_fn, comp_fn, ecto_ty, lower, upper, {lmode, rmode})
    else
      _ -> :error
    end
  end

  @spec dump(Ecto.Type.t(), t, t) :: {:ok, Postgrex.Range.t()} | :error
  def dump(ecto_ty, lower, upper) do
    with {:ok, lower} <- dump_term(ecto_ty, lower),
         {:ok, upper} <- dump_term(ecto_ty, upper) do
      {:ok,
       %Postgrex.Range{
         lower: lower,
         upper: upper,
         lower_inclusive: lower != nil,
         upper_inclusive: false
       }}
    end
  end

  @doc """
  Compute the allen relationship between two proper intervals:

  * before/after:
  ```
    _xxx_____
    _____yyy_
  ```

  * equals:
  ```
    ___xxx___
    ___yyy___
  ```

  * finishes:
  ```
    _____xxx
    ___yyyyy
  ```

  * starts
  ```
    xxx_____
    yyyyy___
  ```

  * meets:
  ```
    xxx_____
    ___yyy__
  ```

  * overlaps:
  ```
    _xxx____
    __yyy___
  ```

  * during:
  ```
    __xxxx__
    _yyyyyy_
  ```
  """
  @spec relation(comp_fn, t, t, t, t) :: allens_relation
  def relation(comp_fn, a_lower, a_upper, b_lower, b_upper) do
    cmp_u_l = comp_term(comp_fn, a_upper, b_lower)
    cmp_u_u = comp_term(comp_fn, a_upper, b_upper)
    cmp_l_l = comp_term(comp_fn, a_lower, b_lower)
    cmp_l_u = comp_term(comp_fn, a_lower, b_upper)

    cond do
      cmp_l_l == :eq and cmp_u_u == :eq ->
        :equals

      cmp_u_u == :eq ->
        :finishes

      cmp_l_l == :eq ->
        :starts

      cmp_u_l == :eq or cmp_l_u == :eq ->
        :meets

      cmp_u_l == :lt ->
        :before

      cmp_l_u == :gt ->
        :after

      cmp_l_l == :lt and cmp_u_u == :gt ->
        :during

      cmp_l_l == :gt and cmp_u_u == :lt ->
        :during

      cmp_l_l == :lt and cmp_u_u != :gt ->
        :overlaps

      cmp_l_l == :gt and cmp_u_u != :lt ->
        :overlaps
    end
  end

  @doc """
  test if the interval contains a point.
  """
  @spec contains?(comp_fn, t, t, t) :: boolean
  def contains?(comp_fn, a, b, c) do
    :gt != comp_term(comp_fn, a, c) and :lt == comp_term(comp_fn, c, b) and :infinity != c and
      :_infinity != c
  end

  @spec succ_term(succ_fn, t) :: t
  defp succ_term(succ_fn, value) do
    case value do
      :infinity -> :infinity
      :_infinity -> :_infinity
      _value -> succ_fn.(value)
    end
  end

  @spec dump_term(Ecto.Type.t(), t) :: {:ok, term} | :error
  defp dump_term(ecto_ty, term) do
    case term do
      :_infinity -> {:ok, nil}
      :infinity -> {:ok, nil}
      _term -> Ecto.Type.dump(ecto_ty, term)
    end
  end

  @spec load_term(:u | :l, Ecto.Type.t(), term) :: {:ok, t} | :error
  defp load_term(mode, ecto_ty, value) do
    case value do
      nil ->
        case mode do
          :u -> {:ok, :infinity}
          :l -> {:ok, :_infinity}
        end

      _value ->
        Ecto.Type.load(ecto_ty, value)
    end
  end

  @spec cast_term(:r | :u, Ecto.Type.t(), term) :: {:ok, t} | :error
  defp cast_term(mode, ecto_ty, term) do
    case term do
      "" ->
        case mode do
          :u -> :infinity
          :l -> :_infinity
        end

      "-infinity" ->
        {:ok, :_infinity}

      "infinity" ->
        {:ok, :infinity}

      :_infinity ->
        {:ok, :_infinity}

      :infinity ->
        {:ok, :infinity}

      _term ->
        Ecto.Type.cast(ecto_ty, term)
    end
  end

  @spec cast_mode(:u | :l, String.t()) :: {:ok, :open} | {:ok, :closed} | :error
  defp cast_mode(dir, c) do
    case {dir, c} do
      {:l, "("} -> {:ok, :open}
      {:l, "["} -> {:ok, :closed}
      {:u, ")"} -> {:ok, :open}
      {:u, "]"} -> {:ok, :closed}
      _ -> :error
    end
  end

  @spec comp_term(comp_fn, t, t) :: :lt | :eq | :gt
  defp comp_term(comp_fn, a, b) do
    case {a, b} do
      {:_infinity, :_infinity} ->
        :eq

      {:infinity, :infinity} ->
        :eq

      {:_infinity, _} ->
        :lt

      {:infinity, _} ->
        :gt

      {_, :infinity} ->
        :lt

      {_, :_infinity} ->
        :gt

      _otherwise ->
        comp_fn.(a, b)
    end
  end
end
