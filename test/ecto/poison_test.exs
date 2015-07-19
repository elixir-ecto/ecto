defmodule Ecto.PoisonTest do
  use ExUnit.Case, async: true

  test "encodes datetimes" do
    time = %Ecto.Time{hour: 1, min: 2, sec: 3}
    assert Poison.encode!(time) == ~s("01:02:03")

    date = %Ecto.Date{year: 2010, month: 4, day: 17}
    assert Poison.encode!(date) == ~s("2010-04-17")

    dt = %Ecto.DateTime{year: 2010, month: 4, day: 17, hour: 0, min: 0, sec: 0}
    assert Poison.encode!(dt) == ~s("2010-04-17T00:00:00Z")
  end

  test "encodes decimal" do
    decimal = Decimal.new("1.0")
    assert Poison.encode!(decimal) == ~s("1.0")
  end
end
