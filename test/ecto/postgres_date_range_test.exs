defmodule Ecto.PostgresDateRangeTest do
  use ExUnit.Case, async: true

  alias Ecto.PostgresDateRange

  doctest Ecto.PostgresDateRange, import: true

  describe "cast" do
    test "using postgres range format" do
      assert PostgresDateRange.new(~D[1900-01-01], ~D[1900-02-01], {:closed, :open}) ==
               PostgresDateRange.cast("[1900-01-01,1900-02-01)")

      assert PostgresDateRange.new(~D[1900-01-01], ~D[1900-02-01], {:open, :open}) ==
               PostgresDateRange.cast("(1900-01-01,1900-02-01)")

      assert PostgresDateRange.new(~D[1900-01-01], ~D[1900-02-01], {:closed, :closed}) ==
               PostgresDateRange.cast("[1900-01-01,1900-02-01]")

      assert PostgresDateRange.new(~D[1900-01-01], ~D[1900-02-01], {:open, :closed}) ==
               PostgresDateRange.cast("(1900-01-01,1900-02-01]")
    end

    test "using" do
      assert PostgresDateRange.new(~D[1900-01-01], ~D[1900-02-01]) ==
               PostgresDateRange.cast(PostgresDateRange.new!(~D[1900-01-01], ~D[1900-02-01]))
    end
  end

  describe "load" do
    test "load postgrex range type" do
      for lmode <- [:open, :closed], rmode <- [:open, :closed] do
        assert PostgresDateRange.new(~D[1900-01-01], ~D[1900-02-01], {lmode, rmode}) ==
                 PostgresDateRange.load(%Postgrex.Range{
                   lower: ~D[1900-01-01],
                   upper: ~D[1900-02-01],
                   lower_inclusive: lmode == :closed,
                   upper_inclusive: rmode == :closed
                 })
      end
    end
  end

  describe "dump" do
    test "creates a postgrex range format" do
      assert {:ok,
              %Postgrex.Range{
                lower: ~D[1900-01-01],
                upper: ~D[1900-02-01],
                lower_inclusive: true,
                upper_inclusive: false
              }} == PostgresDateRange.dump(PostgresDateRange.new!(~D[1900-01-01], ~D[1900-02-01]))

      assert {:ok,
              %Postgrex.Range{
                lower: nil,
                upper: ~D[1900-02-01],
                lower_inclusive: false,
                upper_inclusive: false
              }} == PostgresDateRange.dump(PostgresDateRange.new!(:_infinity, ~D[1900-02-01]))

      assert {:ok,
              %Postgrex.Range{
                lower: ~D[1900-01-01],
                upper: nil,
                lower_inclusive: true,
                upper_inclusive: false
              }} == PostgresDateRange.dump(PostgresDateRange.new!(~D[1900-01-01], :infinity))
    end
  end
end
