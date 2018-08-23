defmodule Ecto.DiscreteRangeTest do
  use ExUnit.Case, async: true

  alias Ecto.DiscreteRange

  describe "allen relationships" do
    test "equals" do
      assert :equals == DiscreteRange.relation(&comp_fn/2, 0, 1, 0, 1)

      assert :equals == DiscreteRange.relation(&comp_fn/2, :_infinity, 1, :_infinity, 1)
      assert :equals == DiscreteRange.relation(&comp_fn/2, 0, :infinity, 0, :infinity)

      assert :equals ==
               DiscreteRange.relation(&comp_fn/2, :_infinity, :infinity, :_infinity, :infinity)
    end

    test "during" do
      assert :during == DiscreteRange.relation(&comp_fn/2, 0, 3, 1, 2)
      assert :during == DiscreteRange.relation(&comp_fn/2, 1, 2, 0, 3)

      assert :during == DiscreteRange.relation(&comp_fn/2, :_infinity, 3, 1, 2)
      assert :during == DiscreteRange.relation(&comp_fn/2, 1, 2, :_infinity, 3)

      assert :during == DiscreteRange.relation(&comp_fn/2, 0, :infinity, 1, 2)
      assert :during == DiscreteRange.relation(&comp_fn/2, 1, 2, 0, :infinity)
    end

    test "overlaps" do
      assert :overlaps == DiscreteRange.relation(&comp_fn/2, 0, 2, 1, 3)
      assert :overlaps == DiscreteRange.relation(&comp_fn/2, 1, 3, 0, 2)

      assert :overlaps == DiscreteRange.relation(&comp_fn/2, :_infinity, 2, 1, 3)
      assert :overlaps == DiscreteRange.relation(&comp_fn/2, 1, 3, :_infinity, 2)

      assert :overlaps == DiscreteRange.relation(&comp_fn/2, 0, 2, 1, :infinity)
      assert :overlaps == DiscreteRange.relation(&comp_fn/2, 1, :infinity, 0, 2)
    end

    test "meets" do
      assert :meets == DiscreteRange.relation(&comp_fn/2, 0, 1, 1, 2)
      assert :meets == DiscreteRange.relation(&comp_fn/2, 1, 2, 0, 1)

      assert :meets == DiscreteRange.relation(&comp_fn/2, :_infinity, 1, 1, 2)
      assert :meets == DiscreteRange.relation(&comp_fn/2, 1, 2, :_infinity, 1)

      assert :meets == DiscreteRange.relation(&comp_fn/2, 0, 1, 1, :infinity)
      assert :meets == DiscreteRange.relation(&comp_fn/2, 1, :infinity, 0, 1)
    end

    test "before" do
      assert :before = DiscreteRange.relation(&comp_fn/2, 0, 1, 2, 3)
      assert :before = DiscreteRange.relation(&comp_fn/2, :_infinity, 1, 2, 3)
      assert :before = DiscreteRange.relation(&comp_fn/2, 0, 1, 2, :infinity)
    end

    test "after" do
      assert :after = DiscreteRange.relation(&comp_fn/2, 2, 3, 0, 1)
      assert :after = DiscreteRange.relation(&comp_fn/2, 2, 3, :_infinity, 1)
      assert :after = DiscreteRange.relation(&comp_fn/2, 2, :infinity, 0, 1)
    end

    test "finishes" do
      assert :finishes == DiscreteRange.relation(&comp_fn/2, 0, 2, 1, 2)
      assert :finishes == DiscreteRange.relation(&comp_fn/2, 1, 2, 0, 2)

      assert :finishes == DiscreteRange.relation(&comp_fn/2, :_infinity, 2, 1, 2)
      assert :finishes == DiscreteRange.relation(&comp_fn/2, 1, 2, :_infinity, 2)

      assert :finishes == DiscreteRange.relation(&comp_fn/2, 0, :infinity, 1, :infinity)
      assert :finishes == DiscreteRange.relation(&comp_fn/2, 1, :infinity, 0, :infinity)
    end

    test "starts" do
      assert :starts == DiscreteRange.relation(&comp_fn/2, 0, 2, 0, 1)
      assert :starts == DiscreteRange.relation(&comp_fn/2, 0, 1, 0, 2)

      assert :starts == DiscreteRange.relation(&comp_fn/2, :_infinity, 2, :_infinity, 1)
      assert :starts == DiscreteRange.relation(&comp_fn/2, :_infinity, 1, :_infinity, 2)

      assert :starts == DiscreteRange.relation(&comp_fn/2, 0, :infinity, 0, 1)
      assert :starts == DiscreteRange.relation(&comp_fn/2, 0, 1, 0, :infinity)
    end

    test "moving a interval on a timeline" do
      assert :before == DiscreteRange.relation(&comp_fn/2, 0, 2, 3, 5)
      assert :meets == DiscreteRange.relation(&comp_fn/2, 1, 3, 3, 5)
      assert :overlaps == DiscreteRange.relation(&comp_fn/2, 2, 4, 3, 5)
      assert :equals == DiscreteRange.relation(&comp_fn/2, 3, 5, 3, 5)
      assert :overlaps == DiscreteRange.relation(&comp_fn/2, 4, 6, 3, 5)
      assert :meets == DiscreteRange.relation(&comp_fn/2, 5, 7, 3, 5)
      assert :after == DiscreteRange.relation(&comp_fn/2, 6, 8, 3, 5)
    end
  end

  describe "contains?" do
    test "a point outside the interval" do
      refute DiscreteRange.contains?(&comp_fn/2, 2, 3, 1)
      refute DiscreteRange.contains?(&comp_fn/2, 2, 3, 3)
      refute DiscreteRange.contains?(&comp_fn/2, 2, 3, 4)

      refute DiscreteRange.contains?(&comp_fn/2, 2, :infinity, 1)
      refute DiscreteRange.contains?(&comp_fn/2, :_infinity, 3, 4)
    end

    test "a point in the interval" do
      assert DiscreteRange.contains?(&comp_fn/2, 2, 4, 2)
      assert DiscreteRange.contains?(&comp_fn/2, 2, 4, 3)
    end

    test "an empty interval" do
      refute DiscreteRange.contains?(&comp_fn/2, 2, 2, 2)
    end

    test "infinity is never in the interval" do
      refute DiscreteRange.contains?(&comp_fn/2, :_infinity, :infinity, :infinity)
      refute DiscreteRange.contains?(&comp_fn/2, :_infinity, :infinity, :_infinity)
    end
  end

  describe "new" do
    test "closed, open is the default" do
      assert {:ok, {0, 1}} ==
               DiscreteRange.new(&succ_fn/1, &comp_fn/2, :integer, 0, 1, {:closed, :open})
    end

    test "normalizes the interval in other modes" do
      assert {:ok, {1, 1}} ==
               DiscreteRange.new(&succ_fn/1, &comp_fn/2, :integer, 0, 1, {:open, :open})

      assert {:ok, {1, 2}} ==
               DiscreteRange.new(&succ_fn/1, &comp_fn/2, :integer, 0, 1, {:open, :closed})

      assert {:ok, {0, 2}} ==
               DiscreteRange.new(&succ_fn/1, &comp_fn/2, :integer, 0, 1, {:closed, :closed})
    end

    test "intervals with infinity" do
      for lmode <- [:open, :closed], rmode <- [:open, :closed] do
        assert {:ok, {:_infinity, :infinity}} ==
                 DiscreteRange.new(
                   &succ_fn/1,
                   &comp_fn/2,
                   :integer,
                   :_infinity,
                   :infinity,
                   {lmode, rmode}
                 )
      end
    end

    test "minus infinity" do
      assert {:ok, {:_infinity, 1}} ==
               DiscreteRange.new(
                 &succ_fn/1,
                 &comp_fn/2,
                 :integer,
                 :_infinity,
                 1,
                 {:closed, :open}
               )
    end

    test "infinity" do
      assert {:ok, {0, :infinity}} ==
               DiscreteRange.new(&succ_fn/1, &comp_fn/2, :integer, 0, :infinity, {:closed, :open})
    end

    test "invalid ranges: a > b" do
      assert :error == DiscreteRange.new(&succ_fn/1, &comp_fn/2, :integer, 1, 0, {:closed, :open})
    end
  end

  defp succ_fn(x), do: x + 1

  defp comp_fn(x, y) when is_integer(x) and is_integer(y) do
    cond do
      x < y -> :lt
      x > y -> :gt
      x == y -> :eq
    end
  end
end
