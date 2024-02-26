defmodule Ecto.TypeTest do
  use ExUnit.Case, async: true

  defmodule Custom do
    use Ecto.Type
    def type,      do: :custom
    def load(_),   do: {:ok, :load}
    def dump(_),   do: {:ok, :dump}
    def cast(_),   do: {:ok, :cast}
    def equal?(true, _), do: true
    def equal?(_, _), do: false
    def embed_as(_), do: :dump
  end

  defmodule CustomAny do
    use Ecto.Type
    def type,      do: :any
    def load(_),   do: {:ok, :load}
    def dump(_),   do: {:ok, :dump}
    def cast(_),   do: {:ok, :cast}
  end

  defmodule CustomWithCastError do
    use Ecto.Type

    def type,      do: :any
    def load(_),   do: {:ok, :load}
    def dump(_),   do: {:ok, :dump}
    def cast("a"), do: {:ok, "a"}
    def cast("b"), do: {:error, foo: :bar, value: "b"}
    def cast("c"), do: {:error, foo: :bar, source: [:email], value: "c"}
  end

  defmodule CustomParameterizedTypeWithFormat do
    use Ecto.ParameterizedType

    def init(_options), do: :init
    def type(_), do: :custom
    def load(_, _, _), do: {:ok, :load}
    def dump(_, _, _),  do: {:ok, :dump}
    def cast(_, _),  do: {:ok, :cast}
    def equal?(true, _, _), do: true
    def equal?(_, _, _), do: false
    def embed_as(_, %{embed: embed}), do: embed
    def format(_params), do: "#CustomParameterizedTypeWithFormat<:custom>"
  end

  defmodule CustomParameterizedTypeWithoutFormat do
    use Ecto.ParameterizedType

    def init(_options), do: :init
    def type(_), do: :custom
    def load(_, _, _), do: {:ok, :load}
    def dump(_, _, _),  do: {:ok, :dump}
    def cast(_, _),  do: {:ok, :cast}
    def equal?(true, _, _), do: true
    def equal?(_, _, _), do: false
    def embed_as(_, %{embed: embed}), do: embed
  end

  defmodule Schema do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "" do
      field :a, :integer, source: :abc
      field :b, :integer, virtual: true
      field :c, :integer, default: 0
    end

    def changeset(params, schema) do
      Ecto.Changeset.cast(schema, params, ~w(a))
    end
  end

  import Kernel, except: [match?: 2], warn: false
  import Ecto.Type
  doctest Ecto.Type

  test "embed_as" do
    assert embed_as(:string, :json) == :self
    assert embed_as(:integer, :json) == :self
    assert embed_as(Custom, :json) == :dump
    assert embed_as(CustomAny, :json) == :self
  end

  test "embedded_load" do
    assert embedded_load(:decimal, "1", :json) == {:ok, Decimal.new("1")}
    assert embedded_load(:decimal, "oops", :json) == :error
    assert embedded_load(Custom, :value, :json) == {:ok, :load}
  end

  test "embedded_dump" do
    assert embedded_dump(:decimal, Decimal.new("1"), :json) == {:ok, Decimal.new("1")}
    assert embedded_dump(Custom, :value, :json) == {:ok, :dump}
  end

  test "custom types" do
    assert load(Custom, "foo") == {:ok, :load}
    assert dump(Custom, "foo") == {:ok, :dump}
    assert cast(Custom, "foo") == {:ok, :cast}
    assert cast(CustomWithCastError, "a") == {:ok, "a"}
    assert cast(CustomWithCastError, "b") == {:error, foo: :bar, value: "b"}
    assert cast(CustomWithCastError, "c") == {:error, foo: :bar, source: [:email], value: "c"}

    assert load(Custom, nil) == {:ok, nil}
    assert dump(Custom, nil) == {:ok, nil}
    assert cast(Custom, nil) == {:ok, nil}
    assert cast(CustomWithCastError, nil) == {:ok, nil}

    assert match?(Custom, :any)
    assert match?(:any, Custom)
    assert match?(CustomAny, :boolean)
  end

  test "untyped maps" do
    assert load(:map, %{"a" => 1}) == {:ok, %{"a" => 1}}
    assert load(:map, 1) == :error

    assert dump(:map, %{a: 1}) == {:ok, %{a: 1}}
    assert dump(:map, 1) == :error
  end

  test "typed maps" do
    assert load({:map, :integer}, %{"a" => 1, "b" => 2}) == {:ok, %{"a" => 1, "b" => 2}}
    assert dump({:map, :integer}, %{"a" => 1, "b" => 2}) == {:ok, %{"a" => 1, "b" => 2}}
    assert cast({:map, :integer}, %{"a" => "1", "b" => "2"}) == {:ok, %{"a" => 1, "b" => 2}}

    assert load({:map, :integer}, %{"a" => 1, "b" => nil}) == {:ok, %{"a" => 1, "b" => nil}}
    assert load({:map, :string}, %{"a" => "1", "b" => nil}) == {:ok, %{"a" => "1", "b" => nil}}
    assert dump({:map, :integer}, %{"a" => 1, "b" => nil}) == {:ok, %{"a" => 1, "b" => nil}}
    assert cast({:map, :integer}, %{"a" => "1", "b" => nil}) == {:ok, %{"a" => 1, "b" => nil}}

    assert load({:map, {:array, :integer}}, %{"a" => [0, 0], "b" => [1, 1]}) == {:ok, %{"a" => [0, 0], "b" => [1, 1]}}
    assert dump({:map, {:array, :integer}}, %{"a" => [0, 0], "b" => [1, 1]}) == {:ok, %{"a" => [0, 0], "b" => [1, 1]}}
    assert cast({:map, {:array, :integer}}, %{"a" => [0, 0], "b" => [1, 1]}) == {:ok, %{"a" => [0, 0], "b" => [1, 1]}}

    assert load({:map, :integer}, %{"a" => ""}) == :error
    assert dump({:map, :integer}, %{"a" => ""}) == :error
    assert cast({:map, :integer}, %{"a" => ""}) == :error

    assert load({:map, :integer}, 1) == :error
    assert dump({:map, :integer}, 1) == :error
    assert cast({:map, :integer}, 1) == :error
  end

  test "array" do
    assert load({:array, :integer}, [1]) == {:ok, [1]}
    assert load({:array, :integer}, [1, nil]) == {:ok, [1, nil]}
    assert dump({:array, :integer}, [2]) == {:ok, [2]}
    assert dump({:array, :integer}, [2, nil]) == {:ok, [2, nil]}
    assert cast({:array, :integer}, [3]) == {:ok, [3]}
    assert cast({:array, :integer}, ["3"]) == {:ok, [3]}
    assert cast({:array, :integer}, [3, nil]) == {:ok, [3, nil]}
    assert cast({:array, :integer}, ["3", nil]) == {:ok, [3, nil]}
  end

  test "custom types with array" do
    assert load({:array, Custom}, ["foo"]) == {:ok, [:load]}
    assert dump({:array, Custom}, ["foo"]) == {:ok, [:dump]}
    assert cast({:array, Custom}, ["foo"]) == {:ok, [:cast]}

    assert cast({:array, CustomWithCastError}, ["b"]) ==
             {:error, foo: :bar, value: "b", source: [0]}

    assert cast({:array, CustomWithCastError}, ["a", "a", "a", "b"]) ==
             {:error, foo: :bar, value: "b", source: [3]}

    assert cast({:array, CustomWithCastError}, ["c"]) ==
             {:error, foo: :bar, source: [0, :email], value: "c"}

    assert cast({:array, CustomWithCastError}, ["a", "a", "c", "a"]) ==
             {:error, foo: :bar, source: [2, :email], value: "c"}

    assert load({:array, Custom}, [nil]) == {:ok, [nil]}
    assert dump({:array, Custom}, [nil]) == {:ok, [nil]}
    assert cast({:array, Custom}, [nil]) == {:ok, [nil]}
    assert cast({:array, CustomWithCastError}, [nil]) == {:ok, [nil]}

    assert load({:array, Custom}, nil) == {:ok, nil}
    assert dump({:array, Custom}, nil) == {:ok, nil}
    assert cast({:array, Custom}, nil) == {:ok, nil}
    assert cast({:array, CustomWithCastError}, nil) == {:ok, nil}

    assert load({:array, Custom}, 1) == :error
    assert dump({:array, Custom}, 1) == :error
    assert cast({:array, Custom}, 1) == :error
    assert cast({:array, CustomWithCastError}, 1) == :error

    assert load({:array, Custom}, [:unused], fn Custom, _ -> {:ok, :used} end) == {:ok, [:used]}
    assert dump({:array, Custom}, [:unused], fn Custom, _ -> {:ok, :used} end) == {:ok, [:used]}
  end

  test "custom types with map" do
    assert load({:map, Custom}, %{"x" => "foo"}) == {:ok, %{"x" => :load}}
    assert dump({:map, Custom}, %{"x" => "foo"}) == {:ok, %{"x" => :dump}}
    assert cast({:map, Custom}, %{"x" => "foo"}) == {:ok, %{"x" => :cast}}

    assert cast({:map, CustomWithCastError}, %{"x" => "b"}) ==
             {:error, foo: :bar, value: "b", source: ["x"]}

    assert cast({:map, CustomWithCastError}, %{"x" => "a", "y" => "a", "z" => "a", "u" => "b"}) ==
             {:error, foo: :bar, value: "b", source: ["u"]}

    assert cast({:map, CustomWithCastError}, %{"x" => "c"}) ==
             {:error, foo: :bar, source: ["x", :email], value: "c"}

    assert cast({:map, CustomWithCastError}, %{"x" => "a", "y" => "a", "z" => "c", "u" => "a"}) ==
             {:error, foo: :bar, source: ["z", :email], value: "c"}

    assert load({:map, Custom}, %{"x" => nil}) == {:ok, %{"x" => nil}}
    assert dump({:map, Custom}, %{"x" => nil}) == {:ok, %{"x" => nil}}
    assert cast({:map, Custom}, %{"x" => nil}) == {:ok, %{"x" => nil}}
    assert cast({:map, CustomWithCastError}, %{"x" => nil}) == {:ok, %{"x" => nil}}

    assert load({:map, Custom}, nil) == {:ok, nil}
    assert dump({:map, Custom}, nil) == {:ok, nil}
    assert cast({:map, Custom}, nil) == {:ok, nil}
    assert cast({:map, CustomWithCastError}, nil) == {:ok, nil}

    assert load({:map, Custom}, 1) == :error
    assert dump({:map, Custom}, 1) == :error
    assert cast({:map, Custom}, 1) == :error
    assert cast({:map, CustomWithCastError}, 1) == :error

    assert load({:map, Custom}, %{"a" => :unused}, fn Custom, _ -> {:ok, :used} end) == {:ok, %{"a" => :used}}
    assert dump({:map, Custom}, %{"a" => :unused}, fn Custom, _ -> {:ok, :used} end) == {:ok, %{"a" => :used}}
  end

  test "dump with custom function" do
    dumper = fn :integer, term -> {:ok, term * 2} end
    assert dump({:array, :integer}, [1, 2], dumper) == {:ok, [2, 4]}
    assert dump({:map, :integer}, %{x: 1, y: 2}, dumper) == {:ok, %{x: 2, y: 4}}
  end

  test "in" do
    assert cast({:in, :integer}, ["1", "2", "3"]) == {:ok, [1, 2, 3]}
    assert cast({:in, :integer}, nil) == :error
  end

  test "{:param, :any_datetime}" do
    value = ~N[2010-04-17 14:00:00]
    assert cast({:param, :any_datetime}, value) == {:ok, value}

    value = ~N[2010-04-17 14:00:00.123]
    assert cast({:param, :any_datetime}, value) == {:ok, value}

    value = DateTime.utc_now()
    assert cast({:param, :any_datetime}, value) == {:ok, value}

    value = "2010-04-17 14:00:00"
    assert cast({:param, :any_datetime}, value) == {:ok, ~N[2010-04-17 14:00:00]}

    value = Map.from_struct(~N[2010-04-17 14:00:00])
    assert cast({:param, :any_datetime}, value) == {:ok, ~N[2010-04-17 14:00:00]}

    assert match?(:naive_datetime, {:param, :any_datetime})
    assert match?(:naive_datetime_usec, {:param, :any_datetime})
    assert match?(:utc_datetime, {:param, :any_datetime})
    assert match?(:utc_datetime_usec, {:param, :any_datetime})
    refute match?(:string, {:param, :any_datetime})
  end

  test "integer" do
    assert cast(:integer, String.duplicate("1", 64)) == :error
  end

  test "decimal" do
    assert cast(:decimal, "1.0") == {:ok, Decimal.new("1.0")}
    assert cast(:decimal, 1.0) == {:ok, Decimal.new("1.0")}
    assert cast(:decimal, 1) == {:ok, Decimal.new("1")}
    assert cast(:decimal, Decimal.new("1")) == {:ok, Decimal.new("1")}
    assert cast(:decimal, "nan") == :error
    assert cast(:decimal, "1.0bad") == :error

    assert_raise ArgumentError, ~r"Decimal.new\(\"NaN\"\) is not allowed for type :decimal", fn ->
      cast(:decimal, Decimal.new("NaN"))
    end

    assert dump(:decimal, Decimal.new("1")) == {:ok, Decimal.new("1")}
    assert dump(:decimal, 1.0) == {:ok, Decimal.new("1.0")}
    assert dump(:decimal, 1) == {:ok, Decimal.new("1")}
    assert dump(:decimal, "1.0") == :error
    assert dump(:decimal, "bad") == :error

    assert_raise ArgumentError, ~r"Decimal.new\(\"NaN\"\) is not allowed for type :decimal", fn ->
      dump(:decimal, Decimal.new("nan"))
    end

    assert load(:decimal, 1) == {:ok, Decimal.new(1)}
    assert load(:decimal, 1.0) == {:ok, Decimal.new("1.0")}
    assert load(:decimal, Decimal.new("1.0")) == {:ok, Decimal.new("1.0")}
    assert load(:decimal, "1.0") == :error
  end

  test "maybe" do
    assert dump({:maybe, :decimal}, Decimal.new(1)) == {:ok, Decimal.new(1)}
    assert dump({:maybe, :decimal}, "not decimal") == {:ok, "not decimal"}

    assert load({:maybe, :decimal}, 1) == {:ok, Decimal.new(1)}
    assert load({:maybe, :decimal}, "not decimal") == {:ok, "not decimal"}

    assert cast({:maybe, :decimal}, 1) == {:ok, Decimal.new(1)}
    assert cast({:maybe, :decimal}, "not decimal") == {:ok, "not decimal"}
  end

  describe "embeds" do
    @uuid_string "bfe0888c-5c59-4bb3-adfd-71f0b85d3db7"

    test "one" do
      embed = %Ecto.Embedded{field: :embed, cardinality: :one,
                             owner: __MODULE__, related: Schema}
      type  = {:parameterized, Ecto.Embedded, embed}

      assert {:ok, %Schema{id: @uuid_string, a: 1, c: 0}} =
             adapter_load(Ecto.TestAdapter, type, %{"id" => @uuid_string, "abc" => 1})
      assert {:ok, nil} == adapter_load(Ecto.TestAdapter, type, nil)
      assert :error == adapter_load(Ecto.TestAdapter, type, 1)

      assert {:ok, %{abc: 1, c: 0, id: @uuid_string}} ==
             adapter_dump(Ecto.TestAdapter, type, %Schema{id: @uuid_string, a: 1})
      assert {:ok, nil} = adapter_dump(Ecto.TestAdapter, type, nil)
      assert :error = adapter_dump(Ecto.TestAdapter, type, 1)

      assert :error == cast(type, %{"a" => 1})
      assert cast(type, %Schema{}) == {:ok, %Schema{}}
      assert cast(type, nil) == {:ok, nil}
    end

    test "many" do
      embed = %Ecto.Embedded{field: :embed, cardinality: :many,
                             owner: __MODULE__, related: Schema}
      type  = {:parameterized, Ecto.Embedded, embed}

      assert {:ok, [%Schema{id: @uuid_string, a: 1, c: 0}]} =
             adapter_load(Ecto.TestAdapter, type, [%{"id" => @uuid_string, "abc" => 1}])
      assert {:ok, []} == adapter_load(Ecto.TestAdapter, type, nil)
      assert :error == adapter_load(Ecto.TestAdapter, type, 1)

      assert {:ok, [%{id: @uuid_string, abc: 1, c: 0}]} ==
             adapter_dump(Ecto.TestAdapter, type, [%Schema{id: @uuid_string, a: 1}])
      assert {:ok, nil} = adapter_dump(Ecto.TestAdapter, type, nil)
      assert :error = adapter_dump(Ecto.TestAdapter, type, 1)

      assert cast(type, [%{"abc" => 1}]) == :error
      assert cast(type, [%Schema{}]) == {:ok, [%Schema{}]}
      assert cast(type, []) == {:ok, []}
    end
  end

  @date ~D[2015-12-31]
  @leap_date ~D[2000-02-29]
  @date_unix_epoch ~D[1970-01-01]

  describe "date" do
    test "cast" do
      assert Ecto.Type.cast(:date, @date) == {:ok, @date}

      assert Ecto.Type.cast(:date, "2015-12-31") == {:ok, @date}
      assert Ecto.Type.cast(:date, "2000-02-29") == {:ok, @leap_date}
      assert Ecto.Type.cast(:date, "2015-00-23") == :error
      assert Ecto.Type.cast(:date, "2015-13-23") == :error
      assert Ecto.Type.cast(:date, "2015-01-00") == :error
      assert Ecto.Type.cast(:date, "2015-01-32") == :error
      assert Ecto.Type.cast(:date, "2015-02-29") == :error
      assert Ecto.Type.cast(:date, "1900-02-29") == :error

      assert Ecto.Type.cast(:date, %{"year" => "2015", "month" => "12", "day" => "31"}) ==
             {:ok, @date}
      assert Ecto.Type.cast(:date, %{year: 2015, month: 12, day: 31}) ==
             {:ok, @date}
      assert Ecto.Type.cast(:date, %{"year" => "", "month" => "", "day" => ""}) ==
             {:ok, nil}
      assert Ecto.Type.cast(:date, %{year: nil, month: nil, day: nil}) ==
             {:ok, nil}
      assert Ecto.Type.cast(:date, %{"year" => "2015", "month" => "", "day" => "31"}) ==
             :error
      assert Ecto.Type.cast(:date, %{"year" => "2015", "month" => nil, "day" => "31"}) ==
             :error
      assert Ecto.Type.cast(:date, %{"year" => "2015", "month" => nil}) ==
             :error
      assert Ecto.Type.cast(:date, %{"year" => "", "month" => "01", "day" => "30"}) ==
             :error
      assert Ecto.Type.cast(:date, %{"year" => nil, "month" => "01", "day" => "30"}) ==
             :error

      assert Ecto.Type.cast(:date, DateTime.from_unix!(10)) ==
             {:ok, @date_unix_epoch}
      assert Ecto.Type.cast(:date, ~N[1970-01-01 12:23:34]) ==
             {:ok, @date_unix_epoch}
      assert Ecto.Type.cast(:date, @date) ==
             {:ok, @date}
      assert Ecto.Type.cast(:date, ~T[12:23:34]) ==
             :error

      assert Ecto.Type.cast(:date, "2015-12-31T00:00:00") == {:ok, @date}
      assert Ecto.Type.cast(:date, "2015-12-31 00:00:00") == {:ok, @date}
    end

    test "dump" do
      assert Ecto.Type.dump(:date, @date) == {:ok, @date}
      assert Ecto.Type.dump(:date, @leap_date) == {:ok, @leap_date}
      assert Ecto.Type.dump(:date, @date_unix_epoch) ==  {:ok, @date_unix_epoch}
    end

    test "load" do
      assert Ecto.Type.load(:date, @date) == {:ok, @date}
      assert Ecto.Type.load(:date, @leap_date) == {:ok, @leap_date}
      assert Ecto.Type.load(:date, @date_unix_epoch) ==  {:ok, @date_unix_epoch}
    end
  end

  @time ~T[23:50:07]
  @time_zero ~T[23:50:00]
  @time_zero_usec ~T[23:50:00.000000]
  @time_usec ~T[23:50:07.030000]

  describe "time" do
    test "cast" do
      assert Ecto.Type.cast(:time, @time) == {:ok, @time}
      assert Ecto.Type.cast(:time, @time_usec) == {:ok, @time}
      assert Ecto.Type.cast(:time, @time_zero) ==  {:ok, @time_zero}

      assert Ecto.Type.cast(:time, "23:50") == {:ok, @time_zero}
      assert Ecto.Type.cast(:time, "23:50:07") == {:ok, @time}
      assert Ecto.Type.cast(:time, "23:50:07Z") == {:ok, @time}
      assert Ecto.Type.cast(:time, "23:50:07.030000") == {:ok, @time}
      assert Ecto.Type.cast(:time, "23:50:07.030000Z") == {:ok, @time}

      assert Ecto.Type.cast(:time, "24:01") == :error
      assert Ecto.Type.cast(:time, "00:61") == :error
      assert Ecto.Type.cast(:time, "00:00.123") == :error
      assert Ecto.Type.cast(:time, "00:00Z") == :error
      assert Ecto.Type.cast(:time, "24:01:01") == :error
      assert Ecto.Type.cast(:time, "00:61:00") == :error
      assert Ecto.Type.cast(:time, "00:00:61") == :error
      assert Ecto.Type.cast(:time, "00:00:009") == :error
      assert Ecto.Type.cast(:time, "00:00:00.A00") == :error

      assert Ecto.Type.cast(:time, %{"hour" => "23", "minute" => "50", "second" => "07"}) ==
             {:ok, @time}
      assert Ecto.Type.cast(:time, %{hour: 23, minute: 50, second: 07}) ==
             {:ok, @time}
      assert Ecto.Type.cast(:time, %{"hour" => "", "minute" => ""}) ==
             {:ok, nil}
      assert Ecto.Type.cast(:time, %{hour: nil, minute: nil}) ==
             {:ok, nil}
      assert Ecto.Type.cast(:time, %{"hour" => "23", "minute" => "50"}) ==
             {:ok, @time_zero}
      assert Ecto.Type.cast(:time, %{hour: 23, minute: 50}) ==
             {:ok, @time_zero}
      assert Ecto.Type.cast(:time, %{hour: 23, minute: 50, second: 07, microsecond: 30_000}) ==
             {:ok, @time}
      assert Ecto.Type.cast(:time, %{"hour" => 23, "minute" => 50, "second" => 07, "microsecond" => 30_000}) ==
             {:ok, @time}
      assert Ecto.Type.cast(:time, %{"hour" => "", "minute" => "50"}) ==
             :error
      assert Ecto.Type.cast(:time, %{hour: 23, minute: nil}) ==
             :error

      assert Ecto.Type.cast(:time, ~N[2016-11-11 23:30:10]) ==
             {:ok, ~T[23:30:10]}
      assert Ecto.Type.cast(:time, ~D[2016-11-11]) ==
             :error
    end

    test "dump" do
      assert Ecto.Type.dump(:time, @time) == {:ok, @time}
      assert Ecto.Type.dump(:time, @time_zero) ==  {:ok, @time_zero}

      assert_raise ArgumentError, ~r":time expects microseconds to be empty", fn ->
        Ecto.Type.dump(:time, @time_usec)
      end
    end

    test "load" do
      assert Ecto.Type.load(:time, @time) == {:ok, @time}
      assert Ecto.Type.load(:time, @time_usec) == {:ok, @time}
      assert Ecto.Type.load(:time, @time_zero) ==  {:ok, @time_zero}
    end
  end

  describe "time_usec" do
    test "cast from Time" do
      assert Ecto.Type.cast(:time_usec, @time_usec) == {:ok, @time_usec}
      assert Ecto.Type.cast(:time_usec, @time_zero) ==  {:ok, @time_zero_usec}
    end

    test "cast from binary" do
      assert Ecto.Type.cast(:time_usec, "23:50:00") == {:ok, @time_zero_usec}
      assert Ecto.Type.cast(:time_usec, "23:50:00Z") == {:ok, @time_zero_usec}
      assert Ecto.Type.cast(:time_usec, "23:50:07.03") == {:ok, @time_usec}
      assert Ecto.Type.cast(:time_usec, "23:50:07.03Z") == {:ok, @time_usec}
      assert Ecto.Type.cast(:time_usec, "23:50:07.030000") == {:ok, @time_usec}
      assert Ecto.Type.cast(:time_usec, "23:50:07.030000Z") == {:ok, @time_usec}

      assert Ecto.Type.cast(:time_usec, "24:01:01") == :error
      assert Ecto.Type.cast(:time_usec, "00:61:00") == :error
      assert Ecto.Type.cast(:time_usec, "00:00:61") == :error
      assert Ecto.Type.cast(:time_usec, "00:00:009") == :error
      assert Ecto.Type.cast(:time_usec, "00:00:00.A00") == :error
    end

    test "cast from map" do
      assert Ecto.Type.cast(:time_usec, %{"hour" => "23", "minute" => "50", "second" => "00"}) == {:ok, @time_zero_usec}
      assert Ecto.Type.cast(:time_usec, %{hour: 23, minute: 50, second: 0}) == {:ok, @time_zero_usec}
      assert Ecto.Type.cast(:time_usec, %{"hour" => "", "minute" => ""}) == {:ok, nil}
      assert Ecto.Type.cast(:time_usec, %{hour: nil, minute: nil}) == {:ok, nil}
      assert Ecto.Type.cast(:time_usec, %{"hour" => "23", "minute" => "50"}) == {:ok, @time_zero_usec}
      assert Ecto.Type.cast(:time_usec, %{hour: 23, minute: 50}) == {:ok, @time_zero_usec}
      assert Ecto.Type.cast(:time_usec, %{hour: 23, minute: 50, second: 07, microsecond: 30_000}) == {:ok, @time_usec}
      assert Ecto.Type.cast(:time_usec, %{"hour" => 23, "minute" => 50, "second" => 07, "microsecond" => 30_000}) == {:ok, @time_usec}
      assert Ecto.Type.cast(:time_usec, %{"hour" => "", "minute" => "50"}) == :error
      assert Ecto.Type.cast(:time_usec, %{hour: 23, minute: nil}) == :error
    end

    test "cast from NaiveDateTime" do
      assert Ecto.Type.cast(:time_usec, ~N[2016-11-11 23:30:10]) == {:ok, ~T[23:30:10.000000]}
    end

    test "cast from DateTime" do
      utc_datetime = DateTime.from_naive!(~N[2016-11-11 23:30:10], "Etc/UTC")
      assert Ecto.Type.cast(:time_usec, utc_datetime) == {:ok, ~T[23:30:10.000000]}
    end

    test "cast from Date" do
      assert Ecto.Type.cast(:time_usec, ~D[2016-11-11]) == :error
    end

    test "dump" do
      assert Ecto.Type.dump(:time_usec, @time_usec) == {:ok, @time_usec}

      assert_raise ArgumentError, ~r":time_usec expects microsecond precision", fn ->
        Ecto.Type.dump(:time_usec, @time)
      end
    end

    test "load" do
      assert Ecto.Type.load(:time_usec, @time_usec) == {:ok, @time_usec}
      assert Ecto.Type.load(:time_usec, @time_zero) ==  {:ok, @time_zero_usec}
    end
  end

  @datetime ~N[2015-01-23 23:50:07]
  @datetime_zero ~N[2015-01-23 23:50:00]
  @datetime_zero_usec ~N[2015-01-23 23:50:00.000000]
  @datetime_usec ~N[2015-01-23 23:50:07.008000]
  @datetime_leapyear ~N[2000-02-29 23:50:07]
  @datetime_leapyear_usec ~N[2000-02-29 23:50:07.000000]

  describe "naive_datetime" do
    test "casting naive datetime" do
      assert Ecto.Type.cast(:naive_datetime, @datetime) == {:ok, @datetime}
      assert Ecto.Type.cast(:naive_datetime, @datetime_usec) == {:ok, @datetime}
      assert Ecto.Type.cast(:naive_datetime, @datetime_leapyear) == {:ok, @datetime_leapyear}

      assert Ecto.Type.cast(:naive_datetime, "2015-01-23 23:50") == {:ok, @datetime_zero}
      assert Ecto.Type.cast(:naive_datetime, "2015-01-23 23:50:07") == {:ok, @datetime}
      assert Ecto.Type.cast(:naive_datetime, "2015-01-23T23:50:07") == {:ok, @datetime}
      assert Ecto.Type.cast(:naive_datetime, "2015-01-23T23:50:07Z") == {:ok, @datetime}
      assert Ecto.Type.cast(:naive_datetime, "2000-02-29T23:50:07") == {:ok, @datetime_leapyear}

      assert Ecto.Type.cast(:naive_datetime, "2015-01-23T23:50:07.008000") == {:ok, @datetime}
      assert Ecto.Type.cast(:naive_datetime, "2015-01-23T23:50:07.008000Z") == {:ok, @datetime}

      assert Ecto.Type.cast(:naive_datetime, "2015-01-23P23:50:07") == :error
      assert Ecto.Type.cast(:naive_datetime, "2015-01-23 23:50.123") == :error
      assert Ecto.Type.cast(:naive_datetime, "2015-01-23 23:50Z") == :error

      assert Ecto.Type.cast(:naive_datetime, %{"year" => "2015", "month" => "1", "day" => "23",
                                               "hour" => "23", "minute" => "50", "second" => "07"}) ==
             {:ok, @datetime}

      assert Ecto.Type.cast(:naive_datetime, %{year: 2015, month: 1, day: 23, hour: 23, minute: 50, second: 07}) ==
             {:ok, @datetime}

      assert Ecto.Type.cast(:naive_datetime, %{"year" => "", "month" => "", "day" => "",
                                               "hour" => "", "minute" => ""}) ==
             {:ok, nil}

      assert Ecto.Type.cast(:naive_datetime, %{year: nil, month: nil, day: nil, hour: nil, minute: nil}) ==
             {:ok, nil}

      assert Ecto.Type.cast(:naive_datetime, %{"year" => "2015", "month" => "1", "day" => "23",
                                               "hour" => "23", "minute" => "50"}) ==
             {:ok, @datetime_zero}

      assert Ecto.Type.cast(:naive_datetime, %{year: 2015, month: 1, day: 23, hour: 23, minute: 50}) ==
             {:ok, @datetime_zero}

      assert Ecto.Type.cast(:naive_datetime, %{year: 2015, month: 1, day: 23, hour: 23,
                                               minute: 50, second: 07, microsecond: 8_000}) ==
             {:ok, @datetime}

      assert Ecto.Type.cast(:naive_datetime, %{"year" => 2015, "month" => 1, "day" => 23,
                                               "hour" => 23, "minute" => 50, "second" => 07,
                                               "microsecond" => 8_000}) ==
             {:ok, @datetime}

      assert Ecto.Type.cast(:naive_datetime, %{"year" => "2015", "month" => "1", "day" => "23",
                                               "hour" => "", "minute" => "50"}) ==
             :error

      assert Ecto.Type.cast(:naive_datetime, %{year: 2015, month: 1, day: 23, hour: 23, minute: nil}) ==
             :error

      assert Ecto.Type.cast(:naive_datetime, %{"year" => "", "month" => "", "day" => "",
                                               "hour" => "23", "minute" => "50", "second" => "07"}) ==
             :error

      assert Ecto.Type.cast(:naive_datetime, %{year: nil, month: nil, day: nil, hour: 23, minute: 50, second: 07}) ==
             :error

      assert Ecto.Type.cast(:naive_datetime, %{"year" => "2015", "month" => "1", "day" => "23",
                                               "hour" => "", "minute" => ""}) ==
             :error

      assert Ecto.Type.cast(:naive_datetime, %{year: 2015, month: 1, day: 23, hour: nil, minute: nil}) ==
             :error

      assert Ecto.Type.cast(:naive_datetime, DateTime.from_unix!(10, :second)) ==
             {:ok, ~N[1970-01-01 00:00:10]}

      assert Ecto.Type.cast(:naive_datetime, @time) == :error
      assert Ecto.Type.cast(:naive_datetime, 1) == :error
    end

    test "cast negative datetime" do
      datetime = NaiveDateTime.from_iso8601!("-2015-01-23 23:50:07Z")
      datetime_zero = NaiveDateTime.from_iso8601!("-2015-01-23 23:50:00Z")

      assert Ecto.Type.cast(:naive_datetime, "-2015-01-23 23:50") == {:ok, datetime_zero}
      assert Ecto.Type.cast(:naive_datetime, "-2015-01-23 23:50:07") == {:ok, datetime}
      assert Ecto.Type.cast(:naive_datetime, "-2015-01-23 23:50:07bad") == :error
    end

    test "dump" do
      assert Ecto.Type.dump(:naive_datetime, @datetime) == {:ok, @datetime}
      assert Ecto.Type.dump(:naive_datetime, @datetime_zero) == {:ok, @datetime_zero}
      assert Ecto.Type.dump(:naive_datetime, @datetime_leapyear) == {:ok, @datetime_leapyear}

      assert_raise ArgumentError, ~r":naive_datetime expects microseconds to be empty", fn ->
        Ecto.Type.dump(:naive_datetime, @datetime_usec)
      end
    end

    test "load" do
      assert Ecto.Type.load(:naive_datetime, @datetime) == {:ok, @datetime}
      assert Ecto.Type.load(:naive_datetime, @datetime_zero) == {:ok, @datetime_zero}
      assert Ecto.Type.load(:naive_datetime, @datetime_usec) == {:ok, @datetime}
      assert Ecto.Type.load(:naive_datetime, @datetime_leapyear) == {:ok, @datetime_leapyear}

      assert Ecto.Type.load(:naive_datetime, DateTime.from_naive!(@datetime, "Etc/UTC")) ==
             {:ok, @datetime}
      assert Ecto.Type.load(:naive_datetime, DateTime.from_naive!(@datetime_zero, "Etc/UTC")) ==
             {:ok, @datetime_zero}
      assert Ecto.Type.load(:naive_datetime, DateTime.from_naive!(@datetime_usec, "Etc/UTC")) ==
             {:ok, @datetime}
      assert Ecto.Type.load(:naive_datetime, DateTime.from_naive!(@datetime_leapyear, "Etc/UTC")) ==
             {:ok, @datetime_leapyear}
    end
  end

  describe "naive_datetime_usec" do
    test "cast from NaiveDateTime" do
      assert Ecto.Type.cast(:naive_datetime_usec, @datetime_zero) == {:ok, @datetime_zero_usec}
      assert Ecto.Type.cast(:naive_datetime_usec, @datetime_usec) == {:ok, @datetime_usec}
      assert Ecto.Type.cast(:naive_datetime_usec, @datetime_leapyear) == {:ok, @datetime_leapyear_usec}
    end

    test "cast from binary" do
      assert Ecto.Type.cast(:naive_datetime_usec, "2015-01-23 23:50:00") == {:ok, @datetime_zero_usec}
      assert Ecto.Type.cast(:naive_datetime_usec, "2015-01-23T23:50:00") == {:ok, @datetime_zero_usec}
      assert Ecto.Type.cast(:naive_datetime_usec, "2015-01-23T23:50:00Z") == {:ok, @datetime_zero_usec}
      assert Ecto.Type.cast(:naive_datetime_usec, "2000-02-29T23:50:07") == {:ok, @datetime_leapyear_usec}
      assert Ecto.Type.cast(:naive_datetime_usec, "2015-01-23T23:50:07.008000") == {:ok, @datetime_usec}
      assert Ecto.Type.cast(:naive_datetime_usec, "2015-01-23T23:50:07.008000Z") == {:ok, @datetime_usec}

      assert Ecto.Type.cast(:naive_datetime_usec, "2015-01-23P23:50:07") == :error
    end

    test "cast from map" do
      term = %{"year" => "2015", "month" => "1", "day" => "23", "hour" => "23", "minute" => "50", "second" => "00"}
      assert Ecto.Type.cast(:naive_datetime_usec, term) == {:ok, @datetime_zero_usec}

      term = %{year: 2015, month: 1, day: 23, hour: 23, minute: 50, second: 0}
      assert Ecto.Type.cast(:naive_datetime_usec, term) == {:ok, @datetime_zero_usec}

      term = %{"year" => "", "month" => "", "day" => "", "hour" => "", "minute" => ""}
      assert Ecto.Type.cast(:naive_datetime_usec, term) == {:ok, nil}

      term = %{year: nil, month: nil, day: nil, hour: nil, minute: nil}
      assert Ecto.Type.cast(:naive_datetime_usec, term) == {:ok, nil}

      term = %{"year" => "2015", "month" => "1", "day" => "23", "hour" => "23", "minute" => "50"}
      assert Ecto.Type.cast(:naive_datetime_usec, term) == {:ok, @datetime_zero_usec}

      term = %{year: 2015, month: 1, day: 23, hour: 23, minute: 50}
      assert Ecto.Type.cast(:naive_datetime_usec, term) == {:ok, @datetime_zero_usec}

      term = %{year: 2015, month: 1, day: 23, hour: 23, minute: 50, second: 07, microsecond: 8_000}
      assert Ecto.Type.cast(:naive_datetime_usec, term) == {:ok, @datetime_usec}

      term = %{
        "year" => 2015, "month" => 1, "day" => 23,
        "hour" => 23, "minute" => 50, "second" => 07, "microsecond" => 8_000
      }
      assert Ecto.Type.cast(:naive_datetime_usec, term) == {:ok, @datetime_usec}

      term = %{
        "year" => "2015", "month" => "1", "day" => "23",
        "hour" => "", "minute" => "50"
      }
      assert Ecto.Type.cast(:naive_datetime_usec, term) == :error

      term = %{year: 2015, month: 1, day: 23, hour: 23, minute: nil}
      assert Ecto.Type.cast(:naive_datetime_usec, term) == :error
    end

    test "cast from DateTime" do
      assert Ecto.Type.cast(:naive_datetime_usec, DateTime.from_unix!(10, :second)) == {:ok, ~N[1970-01-01 00:00:10.000000]}
    end

    test "cast from Time" do
      assert Ecto.Type.cast(:naive_datetime_usec, ~T[23:50:07]) == :error
    end

    test "cast from integer" do
      assert Ecto.Type.cast(:naive_datetime_usec, 1) == :error
    end

    test "dump" do
      assert Ecto.Type.dump(:naive_datetime_usec, @datetime_usec) == {:ok, @datetime_usec}
      assert Ecto.Type.dump(:naive_datetime_usec, @datetime_leapyear_usec) == {:ok, @datetime_leapyear_usec}

      assert_raise ArgumentError, ~r":naive_datetime_usec expects microsecond precision", fn ->
        Ecto.Type.dump(:naive_datetime_usec, @datetime)
      end
    end

    test "load" do
      assert Ecto.Type.load(:naive_datetime_usec, @datetime_usec) == {:ok, @datetime_usec}
      assert Ecto.Type.load(:naive_datetime_usec, @datetime_leapyear_usec) == {:ok, @datetime_leapyear_usec}
    end
  end

  @datetime ~U[2015-01-23 23:50:07Z]
  @datetime_zero ~U[2015-01-23 23:50:00Z]
  @datetime_zero_usec ~U[2015-01-23 23:50:00.000000Z]
  @datetime_usec ~U[2015-01-23 23:50:07.008000Z]
  @datetime_usec_tz %DateTime{
    calendar: Calendar.ISO,
    day: 24,
    hour: 0,
    microsecond: {8000, 6},
    minute: 50,
    month: 1,
    second: 7,
    std_offset: 0,
    time_zone: "Europe/Berlin",
    utc_offset: 3600,
    year: 2015,
    zone_abbr: "CET"
  }
  @datetime_leapyear ~U[2000-02-29 23:50:07Z]
  @datetime_leapyear_usec ~U[2000-02-29 23:50:07.008000Z]

  describe "utc_datetime" do
    test "cast" do
      assert Ecto.Type.cast(:utc_datetime, @datetime) == {:ok, @datetime}
      assert Ecto.Type.cast(:utc_datetime, @datetime_usec) == {:ok, @datetime}
      assert Ecto.Type.cast(:utc_datetime, @datetime_leapyear) == {:ok, @datetime_leapyear}

      assert Ecto.Type.cast(:utc_datetime, "2015-01-23 23:50") == {:ok, @datetime_zero}
      assert Ecto.Type.cast(:utc_datetime, "2015-01-23 23:50:07") == {:ok, @datetime}
      assert Ecto.Type.cast(:utc_datetime, "2015-01-23T23:50:07") == {:ok, @datetime}
      assert Ecto.Type.cast(:utc_datetime, "2015-01-23T23:50:07Z") == {:ok, @datetime}
      assert Ecto.Type.cast(:utc_datetime, "2015-01-24T09:50:07+10:00") == {:ok, @datetime}
      assert Ecto.Type.cast(:utc_datetime, "2000-02-29T23:50:07") == {:ok, @datetime_leapyear}

      assert Ecto.Type.cast(:utc_datetime, "2015-01-23T23:50:07.008000") == {:ok, @datetime}
      assert Ecto.Type.cast(:utc_datetime, "2015-01-23T23:50:07.008000Z") == {:ok, @datetime}
      assert Ecto.Type.cast(:utc_datetime, "2015-01-23T17:50:07.008000-06:00") == {:ok, @datetime}

      assert Ecto.Type.cast(:utc_datetime, "2015-01-23P23:50:07") == :error
      assert Ecto.Type.cast(:utc_datetime, "2015-01-23 23:50.123") == :error
      assert Ecto.Type.cast(:utc_datetime, "2015-01-23 23:50Z") == :error

      assert Ecto.Type.cast(:utc_datetime, %{"year" => "2015", "month" => "1", "day" => "23",
                                             "hour" => "23", "minute" => "50", "second" => "07"}) ==
             {:ok, @datetime}

      assert Ecto.Type.cast(:utc_datetime, %{year: 2015, month: 1, day: 23, hour: 23, minute: 50, second: 07}) ==
             {:ok, @datetime}

      assert Ecto.Type.cast(:utc_datetime, %DateTime{calendar: Calendar.ISO, year: 2015, month: 1, day: 24,
                                                     hour: 9, minute: 50, second: 7, microsecond: {0, 0},
                                                     std_offset: 0, utc_offset: 36000,
                                                     time_zone: "Etc/GMT-10", zone_abbr: "+10"}) ==
             {:ok, @datetime}

      assert Ecto.Type.cast(:utc_datetime, %{"year" => "", "month" => "", "day" => "",
                                             "hour" => "", "minute" => ""}) ==
             {:ok, nil}

      assert Ecto.Type.cast(:utc_datetime, %{year: nil, month: nil, day: nil, hour: nil, minute: nil}) ==
             {:ok, nil}

      assert Ecto.Type.cast(:utc_datetime, %{"year" => "2015", "month" => "1", "day" => "23",
                                             "hour" => "23", "minute" => "50"}) ==
             {:ok, @datetime_zero}

      assert Ecto.Type.cast(:utc_datetime, %{year: 2015, month: 1, day: 23, hour: 23, minute: 50}) ==
             {:ok, @datetime_zero}

      assert Ecto.Type.cast(:utc_datetime, %{year: 2015, month: 1, day: 23, hour: 23,
                                               minute: 50, second: 07, microsecond: 8_000}) ==
             {:ok, @datetime}

      assert Ecto.Type.cast(:utc_datetime, %{"year" => 2015, "month" => 1, "day" => 23,
                                             "hour" => 23, "minute" => 50, "second" => 07,
                                             "microsecond" => 8_000}) ==
             {:ok, @datetime}

      assert Ecto.Type.cast(:utc_datetime, %{"year" => "2015", "month" => "1", "day" => "23",
                                             "hour" => "", "minute" => "50"}) ==
             :error

      assert Ecto.Type.cast(:utc_datetime, %{year: 2015, month: 1, day: 23, hour: 23, minute: nil}) ==
             :error

      assert Ecto.Type.cast(:utc_datetime, ~T[12:23:34]) == :error
      assert Ecto.Type.cast(:utc_datetime, 1) == :error
    end

    test "cast negative datetime" do
      assert Ecto.Type.cast(:utc_datetime, "-2015-01-23 23:50") == {:ok, ~U[-2015-01-23 23:50:00Z]}
      assert Ecto.Type.cast(:utc_datetime, "-2015-01-23 23:50:07") == {:ok, ~U[-2015-01-23 23:50:07Z]}
      assert Ecto.Type.cast(:utc_datetime, "-2015-01-23 23:50:07bad") == :error
    end

    test "dump" do
      assert Ecto.Type.dump(:utc_datetime, @datetime) == {:ok, @datetime}
      assert Ecto.Type.dump(:utc_datetime, @datetime_zero) == {:ok, @datetime_zero}
      assert Ecto.Type.dump(:utc_datetime, @datetime_leapyear) == {:ok, @datetime_leapyear}

      assert_raise ArgumentError, ~r":utc_datetime expects microseconds to be empty", fn ->
        Ecto.Type.dump(:utc_datetime, @datetime_usec)
      end
    end

    test "load" do
      assert Ecto.Type.load(:utc_datetime, ~N[2015-01-23 23:50:07]) == {:ok, @datetime}
      assert Ecto.Type.load(:utc_datetime, ~N[2015-01-23 23:50:00]) == {:ok, @datetime_zero}
      assert Ecto.Type.load(:utc_datetime, ~N[2015-01-23 23:50:07.008000]) == {:ok, @datetime}
      assert Ecto.Type.load(:utc_datetime, ~N[2000-02-29 23:50:07]) == {:ok, @datetime_leapyear}
      assert Ecto.Type.load(:utc_datetime, @datetime) == {:ok, @datetime}
      assert Ecto.Type.load(:utc_datetime, @datetime_zero) == {:ok, @datetime_zero}
      assert Ecto.Type.load(:utc_datetime, @datetime_usec) == {:ok, @datetime}
      assert Ecto.Type.load(:utc_datetime, @datetime_leapyear) == {:ok, @datetime_leapyear}
    end
  end

  describe "utc_datetime_usec" do
    test "cast from DateTime" do
      assert Ecto.Type.cast(:utc_datetime_usec, @datetime_zero) == {:ok, @datetime_zero_usec}
      assert Ecto.Type.cast(:utc_datetime_usec, @datetime_usec) == {:ok, @datetime_usec}
      assert Ecto.Type.cast(:utc_datetime_usec, @datetime_usec_tz) == {:ok, @datetime_usec}
    end

    test "cast from binary" do
      assert Ecto.Type.cast(:utc_datetime_usec, "2015-01-23 23:50:00") == {:ok, @datetime_zero_usec}
      assert Ecto.Type.cast(:utc_datetime_usec, "2015-01-23T23:50:00") == {:ok, @datetime_zero_usec}
      assert Ecto.Type.cast(:utc_datetime_usec, "2015-01-23T23:50:00Z") == {:ok, @datetime_zero_usec}
      assert Ecto.Type.cast(:utc_datetime_usec, "2015-01-24T09:50:00+10:00") == {:ok, @datetime_zero_usec}
      assert Ecto.Type.cast(:utc_datetime_usec, "2015-01-23T23:50:07.008000") == {:ok, @datetime_usec}
      assert Ecto.Type.cast(:utc_datetime_usec, "2015-01-23T23:50:07.008000Z") == {:ok, @datetime_usec}
      assert Ecto.Type.cast(:utc_datetime_usec, "2015-01-23T17:50:07.008000-06:00") == {:ok, @datetime_usec}
      assert Ecto.Type.cast(:utc_datetime_usec, "2000-02-29T23:50:07.008") == {:ok, @datetime_leapyear_usec}

      assert Ecto.Type.cast(:utc_datetime_usec, "2015-01-23P23:50:07") == :error
    end

    test "cast from map" do
      term = %{
        "year" => "2015", "month" => "1", "day" => "23",
        "hour" => "23", "minute" => "50", "second" => "00"
      }
      assert Ecto.Type.cast(:utc_datetime_usec, term) == {:ok, @datetime_zero_usec}

      term = %{year: 2015, month: 1, day: 23, hour: 23, minute: 50, second: 0}
      assert Ecto.Type.cast(:utc_datetime_usec, term) == {:ok, @datetime_zero_usec}

      term = %DateTime{
        calendar: Calendar.ISO, year: 2015, month: 1, day: 24,
        hour: 9, minute: 50, second: 0, microsecond: {0, 0},
        std_offset: 0, utc_offset: 36000,
        time_zone: "Etc/GMT-10", zone_abbr: "+10"
      }
      assert Ecto.Type.cast(:utc_datetime_usec, term) == {:ok, @datetime_zero_usec}

      term = %DateTime{
        calendar: Calendar.ISO, year: 2015, month: 1, day: 24,
        hour: 9, minute: 50, second: 7, microsecond: {8000, 6},
        std_offset: 0, utc_offset: 36000,
        time_zone: "Etc/GMT-10", zone_abbr: "+10"
      }
      assert Ecto.Type.cast(:utc_datetime_usec, term) == {:ok, @datetime_usec}

      term = %{"year" => "", "month" => "", "day" => "", "hour" => "", "minute" => ""}
      assert Ecto.Type.cast(:utc_datetime_usec, term) == {:ok, nil}

      term = %{year: nil, month: nil, day: nil, hour: nil, minute: nil}
      assert Ecto.Type.cast(:utc_datetime_usec, term) == {:ok, nil}

      term = %{"year" => "2015", "month" => "1", "day" => "23", "hour" => "23", "minute" => "50"}
      assert Ecto.Type.cast(:utc_datetime_usec, term) == {:ok, @datetime_zero_usec}

      term = %{year: 2015, month: 1, day: 23, hour: 23, minute: 50}
      assert Ecto.Type.cast(:utc_datetime_usec, term) == {:ok, @datetime_zero_usec}

      term = %{year: 2015, month: 1, day: 23, hour: 23, minute: 50, second: 07, microsecond: 8_000}
      assert Ecto.Type.cast(:utc_datetime_usec, term) == {:ok, @datetime_usec}

      term = %{
        "year" => 2015, "month" => 1, "day" => 23,
        "hour" => 23, "minute" => 50, "second" => 07, "microsecond" => 8_000
      }
      assert Ecto.Type.cast(:utc_datetime_usec, term) == {:ok, @datetime_usec}

      term = %{"year" => "2015", "month" => "1", "day" => "23", "hour" => "", "minute" => "50"}
      assert Ecto.Type.cast(:utc_datetime_usec, term) == :error

      term = %{year: 2015, month: 1, day: 23, hour: 23, minute: nil}
      assert Ecto.Type.cast(:utc_datetime_usec, term) == :error
    end

    test "cast from Time" do
      assert Ecto.Type.cast(:utc_datetime_usec, ~T[12:23:34]) == :error
    end

    test "cast from integer" do
      assert Ecto.Type.cast(:utc_datetime_usec, 1) == :error
    end

    test "dump" do
      assert Ecto.Type.dump(:utc_datetime_usec, @datetime_usec) == DateTime.from_naive(~N[2015-01-23 23:50:07.008000], "Etc/UTC")

      assert_raise ArgumentError, ~r":utc_datetime_usec expects microsecond precision", fn ->
        Ecto.Type.dump(:utc_datetime_usec, @datetime)
      end
    end

    test "load" do
      assert Ecto.Type.load(:utc_datetime_usec, @datetime_usec) == {:ok, @datetime_usec}
      assert Ecto.Type.load(:utc_datetime_usec, ~N[2015-01-23 23:50:07.008000]) == {:ok, @datetime_usec}
      assert Ecto.Type.load(:utc_datetime_usec, ~N[2000-02-29 23:50:07.008000]) == {:ok, @datetime_leapyear_usec}
      assert Ecto.Type.load(:utc_datetime_usec, @datetime_leapyear_usec) == {:ok, @datetime_leapyear_usec}
      assert Ecto.Type.load(:utc_datetime_usec, @datetime_zero) == {:ok, @datetime_zero_usec}
      assert Ecto.Type.load(:utc_datetime_usec, ~D[2018-01-01]) == :error
    end
  end

  describe "equal?/3" do
    test "primitive" do
      assert Ecto.Type.equal?(:integer, 1, 1)
      refute Ecto.Type.equal?(:integer, 1, 2)
      refute Ecto.Type.equal?(:integer, 1, "1")
      refute Ecto.Type.equal?(:integer, 1, nil)
    end

    test "composite primitive" do
      assert Ecto.Type.equal?({:array, :integer}, [1], [1])
      refute Ecto.Type.equal?({:array, :integer}, [1], [2])
      refute Ecto.Type.equal?({:array, :integer}, [1, 1], [1])
      refute Ecto.Type.equal?({:array, :integer}, [1], [1, 1])
    end

    test "semantical comparison" do
      assert Ecto.Type.equal?(:decimal, d(1), d("1.0"))
      refute Ecto.Type.equal?(:decimal, d(1), 1)
      refute Ecto.Type.equal?(:decimal, d(1), d("1.1"))
      refute Ecto.Type.equal?(:decimal, d(1), nil)

      assert Ecto.Type.equal?(:time, ~T[09:00:00], ~T[09:00:00.000000])
      refute Ecto.Type.equal?(:time, ~T[09:00:00], ~T[09:00:00.999999])
      assert Ecto.Type.equal?(:time_usec, ~T[09:00:00], ~T[09:00:00.000000])
      refute Ecto.Type.equal?(:time_usec, ~T[09:00:00], ~T[09:00:00.999999])

      assert Ecto.Type.equal?(:naive_datetime, ~N[2018-01-01 09:00:00], ~N[2018-01-01 09:00:00.000000])
      refute Ecto.Type.equal?(:naive_datetime, ~N[2018-01-01 09:00:00], ~N[2018-01-01 09:00:00.999999])
      assert Ecto.Type.equal?(:naive_datetime_usec, ~N[2018-01-01 09:00:00], ~N[2018-01-01 09:00:00.000000])
      refute Ecto.Type.equal?(:naive_datetime_usec, ~N[2018-01-01 09:00:00], ~N[2018-01-01 09:00:00.999999])

      assert Ecto.Type.equal?(:utc_datetime, utc("2018-01-01 09:00:00"), utc("2018-01-01 09:00:00.000000"))
      refute Ecto.Type.equal?(:utc_datetime, utc("2018-01-01 09:00:00"), utc("2018-01-01 09:00:00.999999"))
      assert Ecto.Type.equal?(:utc_datetime_usec, utc("2018-01-01 09:00:00"), utc("2018-01-01 09:00:00.000000"))
      refute Ecto.Type.equal?(:utc_datetime_usec, utc("2018-01-01 09:00:00"), utc("2018-01-01 09:00:00.999999"))
    end

    test "composite semantical comparison" do
      assert Ecto.Type.equal?({:array, :decimal}, [d(1)], [d("1.0")])
      refute Ecto.Type.equal?({:array, :decimal}, [d(1)], [d("1.1")])
      refute Ecto.Type.equal?({:array, :decimal}, [d(1), d(1)], [d(1)])
      refute Ecto.Type.equal?({:array, :decimal}, [d(1)], [d(1), d(1)])

      assert Ecto.Type.equal?({:array, {:array, :decimal}}, [[d(1)]], [[d("1.0")]])
      refute Ecto.Type.equal?({:array, {:array, :decimal}}, [[d(1)]], [[d("1.1")]])

      assert Ecto.Type.equal?({:map, :decimal}, %{x: d(1)}, %{x: d("1.0")})
    end

    test "custom structural comparison" do
      uuid = "00000000-0000-0000-0000-000000000000"
      assert Ecto.Type.equal?(Ecto.UUID, uuid, uuid)
      refute Ecto.Type.equal?(Ecto.UUID, uuid, "")
    end

    test "custom semantical comparison" do
      assert Ecto.Type.equal?(Custom, true, false)
      refute Ecto.Type.equal?(Custom, false, false)
    end

    test "nil values" do
      assert Ecto.Type.equal?(:any, nil, nil)
      assert Ecto.Type.equal?(:boolean, nil, nil)
      assert Ecto.Type.equal?(:binary, nil, nil)
      assert Ecto.Type.equal?(:binary_id, nil, nil)
      assert Ecto.Type.equal?(:date, nil, nil)
      assert Ecto.Type.equal?(:decimal, nil, nil)
      assert Ecto.Type.equal?(:float, nil, nil)
      assert Ecto.Type.equal?(:id, nil, nil)
      assert Ecto.Type.equal?(:integer, nil, nil)
      assert Ecto.Type.equal?(:map, nil, nil)
      assert Ecto.Type.equal?(:naive_datetime, nil, nil)
      assert Ecto.Type.equal?(:naive_datetime_usec, nil, nil)
      assert Ecto.Type.equal?(:string, nil, nil)
      assert Ecto.Type.equal?(:time, nil, nil)
      assert Ecto.Type.equal?(:time_usec, nil, nil)
      assert Ecto.Type.equal?(:utc_datetime, nil, nil)
      assert Ecto.Type.equal?(:utc_datetime_usec, nil, nil)

      term = [~T[10:10:10], nil]
      assert Ecto.Type.equal?({:array, :time}, term, term)

      term = %{one: nil, two: ~T[10:10:10]}
      assert Ecto.Type.equal?({:map, :time}, term, term)

      assert Ecto.Type.equal?(Custom, nil, nil)
    end
  end

  describe "format/1" do
    test "parameterized type with format/1 defined" do
      params = %{}
      assert Ecto.Type.format({:parameterized, CustomParameterizedTypeWithFormat, params}) == "#CustomParameterizedTypeWithFormat<:custom>"
    end

    test "parameterized type without format/1 defined" do
      type = {:parameterized, CustomParameterizedTypeWithoutFormat, %{key: :value}}
      assert Ecto.Type.format(type) == "#Ecto.TypeTest.CustomParameterizedTypeWithoutFormat<%{key: :value}>"
    end

    test "composite parameterized type" do
      params = %{}
      with_format_defined = {:parameterized, CustomParameterizedTypeWithFormat, params}
      without_format_defined = {:parameterized, CustomParameterizedTypeWithoutFormat, params}

      assert Ecto.Type.format({:array, with_format_defined}) == "{:array, #CustomParameterizedTypeWithFormat<:custom>}"
      assert Ecto.Type.format({:array, without_format_defined}) == "{:array, #Ecto.TypeTest.CustomParameterizedTypeWithoutFormat<%{}>}"
    end

    test "non parameterized type" do
      # fallback to `inspect(type)`
      assert Ecto.Type.format(:id) == ":id"
    end

    test "composite non parameterized type" do
      # fallback to `inspect(type)`
      assert Ecto.Type.format({:array, :id}) == "{:array, :id}"
      assert Ecto.Type.format({:array, {:map, :integer}}) == "{:array, {:map, :integer}}"
    end
  end

  defp d(decimal), do: Decimal.new(decimal)

  defp utc(string) do
    string
    |> NaiveDateTime.from_iso8601!()
    |> DateTime.from_naive!("Etc/UTC")
  end
end
