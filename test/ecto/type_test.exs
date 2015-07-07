defmodule Ecto.TypeTest do
  use ExUnit.Case, async: true

  defmodule Custom do
    @behaviour Ecto.Type
    def type,      do: :custom
    def load(_),   do: {:ok, :load}
    def dump(_),   do: {:ok, :dump}
    def cast(_),   do: {:ok, :cast}
  end

  defmodule Model do
    use Ecto.Model

    @primary_key false
    schema "" do
      field :a, :integer
    end
  end

  import Kernel, except: [match?: 2], warn: false
  import Ecto.Type
  doctest Ecto.Type

  test "custom types" do
    assert load(Custom, "foo") == {:ok, :load}
    assert dump(Custom, "foo") == {:ok, :dump}
    assert cast(Custom, "foo") == {:ok, :cast}

    assert load(Custom, nil) == {:ok, nil}
    assert dump(Custom, nil) == {:ok, %Ecto.Query.Tagged{type: :custom, value: nil}}
    assert cast(Custom, nil) == {:ok, nil}
  end

  test "boolean types" do
    assert load(:boolean, 1) == {:ok, true}
    assert load(:boolean, 0) == {:ok, false}
  end

  test "map types" do
    assert load(:map, "{\"a\": 1}") == {:ok, %{"a" => 1}}
    assert load(:map, %{"a" => 1}) == {:ok, %{"a" => 1}}
    assert load(:map, 1) == :error

    assert dump(:map, %{a: 1}) == {:ok, %{a: 1}}
    assert dump(:map, 1) == :error
  end

  test "embeds_one" do
    type = {:embed, %{cardinality: :one, embed: Model}}
    assert {:ok, %Model{a: 1}} = load(type, %{"a" => 1})
    assert {:ok, %Model{a: 1}} = load(type, "{\"a\": 1}")
    assert :error = load(type, 1)

    assert dump(type, %Model{a: 1}) == {:ok, %{a: 1}}
    assert dump(type, 1) == :error
  end

  test "embeds_many with array" do
    type = {:embed, %{cardinality: :many, container: :array, embed: Model}}
    assert {:ok, [%Model{a: 1}]} = load(type, [%{"a" => 1}])
    assert {:ok, [%Model{a: 1}]} = load(type, ["{\"a\": 1}"])
    assert :error = load(type, 1)

    assert dump(type, [%Model{a: 1}]) == {:ok, [%{a: 1}]}
    assert dump(type, 1) == :error
  end

  test "custom types with array" do
    assert load({:array, Custom}, ["foo"]) == {:ok, [:load]}
    assert dump({:array, Custom}, ["foo"]) == {:ok, [:dump]}
    assert cast({:array, Custom}, ["foo"]) == {:ok, [:cast]}

    assert load({:array, Custom}, [nil]) == {:ok, [nil]}
    assert dump({:array, Custom}, [nil]) == {:ok, %Ecto.Query.Tagged{type: {:array, :custom}, value: [nil]}}
    assert cast({:array, Custom}, [nil]) == {:ok, [nil]}

    assert load({:array, Custom}, 1) == :error
    assert dump({:array, Custom}, 1) == :error
    assert cast({:array, Custom}, 1) == :error
  end

  test "decimal casting" do
    assert cast(:decimal, "1.0") == {:ok, Decimal.new("1.0")}
    assert cast(:decimal, 1.0) == {:ok, Decimal.new("1.0")}
    assert cast(:decimal, 1) == {:ok, Decimal.new("1")}
  end

  test "datetime types" do
    erlang_datetime = {{2015, 5, 27}, {11, 30, 00}}
    assert load(:datetime, erlang_datetime) == {:ok, erlang_datetime}
    assert dump(:datetime, erlang_datetime) == {:ok, erlang_datetime}
    assert cast(:datetime, erlang_datetime) == {:ok, erlang_datetime}

    datetime_with_usec = {{2015, 5, 27}, {11, 30, 00, 27}}
    assert load(:datetime, datetime_with_usec) == {:ok, datetime_with_usec}
    assert dump(:datetime, datetime_with_usec) == {:ok, datetime_with_usec}
    assert cast(:datetime, datetime_with_usec) == {:ok, datetime_with_usec}
  end

  test "time types" do
    erlang_time = {11, 30, 00}
    assert load(:time, erlang_time) == {:ok, erlang_time}
    assert dump(:time, erlang_time) == {:ok, erlang_time}
    assert cast(:time, erlang_time) == {:ok, erlang_time}

    time_with_usec = {11, 30, 00, 27}
    assert load(:time, time_with_usec) == {:ok, time_with_usec}
    assert dump(:time, time_with_usec) == {:ok, time_with_usec}
    assert cast(:time, time_with_usec) == {:ok, time_with_usec}
  end
end
