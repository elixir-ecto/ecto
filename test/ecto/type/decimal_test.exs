defmodule Ecto.Type.DecimalTest do
  use ExUnit.Case, async: true

  import Ecto.Type.Decimal

  test "cast/1" do
    assert cast("1.0") == {:ok, Decimal.new("1.0")}
    assert cast(1.0) == {:ok, Decimal.new("1.0")}
    assert cast(1) == {:ok, Decimal.new("1")}
    assert cast(Decimal.new("1")) == {:ok, Decimal.new("1")}
    assert cast("nan") == :error
    assert cast(Decimal.new("NaN")) == :error
    assert cast(Decimal.new("Infinity")) == :error
  end

  test "dump/1" do
    assert dump(Decimal.new("1")) == {:ok, Decimal.new("1")}
    assert dump(Decimal.new("nan")) == :error
    assert dump("1.0") == :error
    assert dump(1.0) == {:ok, Decimal.new("1.0")}
    assert dump(1) == {:ok, Decimal.new("1")}
  end
end
