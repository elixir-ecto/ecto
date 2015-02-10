defmodule Ecto.TypeTest do
  use ExUnit.Case, async: true

  defmodule Custom do
    @behaviour Ecto.Type
    def type,      do: :custom
    def load(_),   do: {:ok, :load}
    def dump(_),   do: {:ok, :dump}
    def cast(_),   do: {:ok, :cast}
    def blank?(_), do: false
  end

  import Kernel, except: [match?: 2], warn: false
  import Ecto.Type
  doctest Ecto.Type

  test "custom types" do
    assert load(Custom, "foo") == {:ok, :load}
    assert dump(Custom, "foo") == {:ok, :dump}
    assert cast(Custom, "foo") == {:ok, :cast}
    refute blank?(Custom, "foo")

    assert load(Custom, nil) == {:ok, nil}
    assert dump(Custom, nil) == {:ok, nil}
    assert cast(Custom, nil) == {:ok, nil}
    assert blank?(Custom, nil)
  end

  test "boolean types" do
    assert load(:boolean, 1) == {:ok, true}
    assert load(:boolean, 0) == {:ok, false}
  end

  test "custom types with array" do
    assert load({:array, Custom}, ["foo"]) == {:ok, [:load]}
    assert dump({:array, Custom}, ["foo"]) == {:ok, [:dump]}
    assert cast({:array, Custom}, ["foo"]) == {:ok, [:cast]}

    assert load({:array, Custom}, [nil]) == {:ok, [nil]}
    assert dump({:array, Custom}, [nil]) == {:ok, [nil]}
    assert cast({:array, Custom}, [nil]) == {:ok, [nil]}
  end

  test "decimal casting" do
    assert cast(:decimal, "1.0") == {:ok, Decimal.new("1.0")}
    assert cast(:decimal, 1.0) == {:ok, Decimal.new("1.0")}
    assert cast(:decimal, 1) == {:ok, Decimal.new("1")}
  end
end
