defmodule Ecto.TypeTest do
  use ExUnit.Case, async: true

  defmodule Custom do
    @behaviour Ecto.Type
    def type,      do: :custom
    def load(_),   do: {:ok, :load}
    def dump(_),   do: {:ok, :dump}
    def cast(_),   do: {:ok, :cast}
  end

  defmodule CustomAny do
    @behaviour Ecto.Type
    def type,      do: :any
    def load(_),   do: {:ok, :load}
    def dump(_),   do: {:ok, :dump}
    def cast(_),   do: {:ok, :cast}
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

  test "custom types" do
    assert load(Custom, "foo") == {:ok, :load}
    assert dump(Custom, "foo") == {:ok, :dump}
    assert cast(Custom, "foo") == {:ok, :cast}

    assert load(Custom, nil) == {:ok, nil}
    assert dump(Custom, nil) == {:ok, nil}
    assert cast(Custom, nil) == {:ok, nil}

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

  test "custom types with array" do
    assert load({:array, Custom}, ["foo"]) == {:ok, [:load]}
    assert dump({:array, Custom}, ["foo"]) == {:ok, [:dump]}
    assert cast({:array, Custom}, ["foo"]) == {:ok, [:cast]}

    assert load({:array, Custom}, [nil]) == {:ok, [nil]}
    assert dump({:array, Custom}, [nil]) == {:ok, [nil]}
    assert cast({:array, Custom}, [nil]) == {:ok, [nil]}

    assert load({:array, Custom}, nil) == {:ok, nil}
    assert dump({:array, Custom}, nil) == {:ok, nil}
    assert cast({:array, Custom}, nil) == {:ok, nil}

    assert load({:array, Custom}, 1) == :error
    assert dump({:array, Custom}, 1) == :error
    assert cast({:array, Custom}, 1) == :error
  end

  test "in" do
    assert cast({:in, :integer}, ["1", "2", "3"]) == {:ok, [1, 2, 3]}
    assert cast({:in, :integer}, nil) == :error
  end

  test "decimal" do
    assert cast(:decimal, "1.0") == {:ok, Decimal.new("1.0")}
    assert cast(:decimal, 1.0) == {:ok, Decimal.new("1.0")}
    assert cast(:decimal, 1) == {:ok, Decimal.new("1")}
    assert cast(:decimal, Decimal.new("1")) == {:ok, Decimal.new("1")}

    assert dump(:decimal, "1.0") == :error
    assert dump(:decimal, 1.0) == {:ok, Decimal.new("1.0")}
    assert dump(:decimal, 1) == {:ok, Decimal.new("1")}
    assert dump(:decimal, Decimal.new("1")) == {:ok, Decimal.new("1")}
  end

  @uuid_string "bfe0888c-5c59-4bb3-adfd-71f0b85d3db7"
  @uuid_binary <<191, 224, 136, 140, 92, 89, 75, 179, 173, 253, 113, 240, 184, 93, 61, 183>>

  test "embeds_one" do
    embed = %Ecto.Embedded{field: :embed, cardinality: :one,
                           owner: __MODULE__, related: Schema}
    type  = {:embed, embed}

    assert {:ok, %Schema{id: @uuid_string, a: 1, c: 0}} =
           adapter_load(Ecto.TestAdapter, type, %{"id" => @uuid_binary, "abc" => 1})
    assert {:ok, nil} == adapter_load(Ecto.TestAdapter,type, nil)
    assert :error == adapter_load(Ecto.TestAdapter, type, 1)

    assert {:ok, %{abc: 1, c: 0, id: @uuid_binary}} ==
           adapter_dump(Ecto.TestAdapter, type, %Schema{id: @uuid_string, a: 1})

    assert :error == cast(type, %{"a" => 1})
    assert cast(type, %Schema{}) == {:ok, %Schema{}}
    assert cast(type, nil) == {:ok, nil}
    assert match?(:any, type)
  end

  test "embeds_many" do
    embed = %Ecto.Embedded{field: :embed, cardinality: :many,
                           owner: __MODULE__, related: Schema}
    type  = {:embed, embed}

    assert {:ok, [%Schema{id: @uuid_string, a: 1, c: 0}]} =
           adapter_load(Ecto.TestAdapter, type, [%{"id" => @uuid_binary, "abc" => 1}])
    assert {:ok, []} == adapter_load(Ecto.TestAdapter, type, nil)
    assert :error == adapter_load(Ecto.TestAdapter, type, 1)

    assert {:ok, [%{id: @uuid_binary, abc: 1, c: 0}]} ==
           adapter_dump(Ecto.TestAdapter, type, [%Schema{id: @uuid_string, a: 1}])

    assert cast(type, [%{"abc" => 1}]) == :error
    assert cast(type, [%Schema{}]) == {:ok, [%Schema{}]}
    assert cast(type, []) == {:ok, []}
    assert match?({:array, :any}, type)
  end

  @date ~D[2015-12-31]
  @leap_date ~D[2000-02-29]
  @date_unix_epoch ~D[1970-01-01]

  test "date casting" do
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

  @time ~T[23:50:07]
  @time_zero ~T[23:50:00]
  @time_usec ~T[23:50:07.030000]

  test "time casting" do
    assert Ecto.Type.cast(:time, @time) == {:ok, @time}
    assert Ecto.Type.cast(:time, @time_zero) ==  {:ok, @time_zero}

    assert Ecto.Type.cast(:time, "23:50") == {:ok, @time_zero}
    assert Ecto.Type.cast(:time, "23:50:07") == {:ok, @time}
    assert Ecto.Type.cast(:time, "23:50:07Z") == {:ok, @time}
    assert Ecto.Type.cast(:time, "23:50:07.030000") == {:ok, @time_usec}
    assert Ecto.Type.cast(:time, "23:50:07.030000Z") == {:ok, @time_usec}

    assert Ecto.Type.cast(:time, "24:01") == :error
    assert Ecto.Type.cast(:time, "00:61") == :error
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
           {:ok, @time_usec}
    assert Ecto.Type.cast(:time, %{"hour" => 23, "minute" => 50, "second" => 07, "microsecond" => 30_000}) ==
           {:ok, @time_usec}
    assert Ecto.Type.cast(:time, %{"hour" => "", "minute" => "50"}) ==
           :error
    assert Ecto.Type.cast(:time, %{hour: 23, minute: nil}) ==
           :error

    assert Ecto.Type.cast(:time, ~N[2016-11-11 23:30:10]) ==
           {:ok, ~T[23:30:10]}
    assert Ecto.Type.cast(:time, ~D[2016-11-11]) ==
           :error
  end

  @datetime ~N[2015-01-23 23:50:07]
  @datetime_zero ~N[2015-01-23 23:50:00]
  @datetime_usec ~N[2015-01-23 23:50:07.008000]
  @datetime_leapyear ~N[2000-02-29 23:50:07]

  test "casting naive datetime" do
    assert Ecto.Type.cast(:naive_datetime, @datetime) == {:ok, @datetime}
    assert Ecto.Type.cast(:naive_datetime, @datetime_usec) == {:ok, @datetime_usec}
    assert Ecto.Type.cast(:naive_datetime, @datetime_leapyear) == {:ok, @datetime_leapyear}

    assert Ecto.Type.cast(:naive_datetime, "2015-01-23 23:50:07") == {:ok, @datetime}
    assert Ecto.Type.cast(:naive_datetime, "2015-01-23T23:50:07") == {:ok, @datetime}
    assert Ecto.Type.cast(:naive_datetime, "2015-01-23T23:50:07Z") == {:ok, @datetime}
    assert Ecto.Type.cast(:naive_datetime, "2000-02-29T23:50:07") == {:ok, @datetime_leapyear}
    assert Ecto.Type.cast(:naive_datetime, "2015-01-23P23:50:07") == :error

    assert Ecto.Type.cast(:naive_datetime, "2015-01-23T23:50:07.008000") == {:ok, @datetime_usec}
    assert Ecto.Type.cast(:naive_datetime, "2015-01-23T23:50:07.008000Z") == {:ok, @datetime_usec}

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
           {:ok, @datetime_usec}

    assert Ecto.Type.cast(:naive_datetime, %{"year" => 2015, "month" => 1, "day" => 23,
                                             "hour" => 23, "minute" => 50, "second" => 07,
                                             "microsecond" => 8_000}) ==
           {:ok, @datetime_usec}

    assert Ecto.Type.cast(:naive_datetime, %{"year" => "2015", "month" => "1", "day" => "23",
                                             "hour" => "", "minute" => "50"}) ==
           :error

    assert Ecto.Type.cast(:naive_datetime, %{year: 2015, month: 1, day: 23, hour: 23, minute: nil}) ==
           :error

    assert Ecto.Type.cast(:naive_datetime, DateTime.from_unix!(10, :seconds)) ==
           {:ok, ~N[1970-01-01 00:00:10]}

    assert Ecto.Type.cast(:naive_datetime, @time) == :error
    assert Ecto.Type.cast(:naive_datetime, 1) == :error
  end

  @datetime DateTime.from_unix!(1422057007, :seconds)
  @datetime_zero DateTime.from_unix!(1422057000, :seconds)
  @datetime_usec DateTime.from_unix!(1422057007008000, :microseconds)
  @datetime_leapyear DateTime.from_unix!(951868207, :seconds)

  test "casting utc datetime" do
    assert Ecto.Type.cast(:utc_datetime, @datetime) == {:ok, @datetime}
    assert Ecto.Type.cast(:utc_datetime, @datetime_usec) == {:ok, @datetime_usec}
    assert Ecto.Type.cast(:utc_datetime, @datetime_leapyear) == {:ok, @datetime_leapyear}

    assert Ecto.Type.cast(:utc_datetime, "2015-01-23 23:50:07") == {:ok, @datetime}
    assert Ecto.Type.cast(:utc_datetime, "2015-01-23T23:50:07") == {:ok, @datetime}
    assert Ecto.Type.cast(:utc_datetime, "2015-01-23T23:50:07Z") == {:ok, @datetime}
    assert Ecto.Type.cast(:utc_datetime, "2015-01-24T09:50:07+10:00") == {:ok, @datetime}
    assert Ecto.Type.cast(:utc_datetime, "2000-02-29T23:50:07") == {:ok, @datetime_leapyear}
    assert Ecto.Type.cast(:utc_datetime, "2015-01-23P23:50:07") == :error

    assert Ecto.Type.cast(:utc_datetime, "2015-01-23T23:50:07.008000") == {:ok, @datetime_usec}
    assert Ecto.Type.cast(:utc_datetime, "2015-01-23T23:50:07.008000Z") == {:ok, @datetime_usec}
    assert Ecto.Type.cast(:utc_datetime, "2015-01-23T17:50:07.008000-06:00") == {:ok, @datetime_usec}

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
           {:ok, @datetime_usec}

    assert Ecto.Type.cast(:utc_datetime, %{"year" => 2015, "month" => 1, "day" => 23,
                                           "hour" => 23, "minute" => 50, "second" => 07,
                                           "microsecond" => 8_000}) ==
           {:ok, @datetime_usec}

    assert Ecto.Type.cast(:utc_datetime, %{"year" => "2015", "month" => "1", "day" => "23",
                                           "hour" => "", "minute" => "50"}) ==
           :error

    assert Ecto.Type.cast(:utc_datetime, %{year: 2015, month: 1, day: 23, hour: 23, minute: nil}) ==
           :error

    assert Ecto.Type.cast(:utc_datetime, ~T[12:23:34]) == :error
    assert Ecto.Type.cast(:utc_datetime, 1) == :error
  end
end
