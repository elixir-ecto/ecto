defmodule Ecto.TypeTest do
  use ExUnit.Case, async: true

  alias Ecto.TestRepo

  defmodule Custom do
    @behaviour Ecto.Type
    def type,      do: :custom
    def load(_),   do: {:ok, :load}
    def dump(_),   do: {:ok, :dump}
    def cast(_),   do: {:ok, :cast}
    def equal?(true, _), do: true
    def equal?(_, _), do: false
  end

  defmodule CustomAny do
    @behaviour Ecto.Type
    def type,      do: :any
    def load(_),   do: {:ok, :load}
    def dump(_),   do: {:ok, :dump}
    def cast(_),   do: {:ok, :cast}
  end

  defmodule PrefixedID do
    @behaviour Ecto.Type
    def type(), do: :binary_id
    def cast("foo-" <> _ = id), do: {:ok, id}
    def cast(id), do: {:ok, "foo-" <> id}
    def load(uuid), do: {:ok, "foo-" <> uuid}
    def dump("foo-" <> uuid), do: {:ok, uuid}
    def dump(_uuid), do: :error
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

  defmodule PrefixedIDSchema do
    use Ecto.Schema

    @primary_key {:id, PrefixedID, autogenerate: true}
    schema "" do
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

  test "custom types with map" do
    assert load({:map, Custom}, %{"x" => "foo"}) == {:ok, %{"x" => :load}}
    assert dump({:map, Custom}, %{"x" => "foo"}) == {:ok, %{"x" => :dump}}
    assert cast({:map, Custom}, %{"x" => "foo"}) == {:ok, %{"x" => :cast}}

    assert load({:map, Custom}, %{"x" => nil}) == {:ok, %{"x" => nil}}
    assert dump({:map, Custom}, %{"x" => nil}) == {:ok, %{"x" => nil}}
    assert cast({:map, Custom}, %{"x" => nil}) == {:ok, %{"x" => nil}}

    assert load({:map, Custom}, nil) == {:ok, nil}
    assert dump({:map, Custom}, nil) == {:ok, nil}
    assert cast({:map, Custom}, nil) == {:ok, nil}

    assert load({:map, Custom}, 1) == :error
    assert dump({:map, Custom}, 1) == :error
    assert cast({:map, Custom}, 1) == :error
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

  @uuid_string "bfe0888c-5c59-4bb3-adfd-71f0b85d3db7"
  @uuid_binary <<191, 224, 136, 140, 92, 89, 75, 179, 173, 253, 113, 240, 184, 93, 61, 183>>

  test "embeds_one" do
    embed = %Ecto.Embedded{field: :embed, cardinality: :one,
                           owner: __MODULE__, related: Schema}
    type  = {:embed, embed}

    assert {:ok, %Schema{id: @uuid_string, a: 1, c: 0}} =
           adapter_load(Ecto.TestAdapter, type, %{"id" => @uuid_binary, "abc" => 1})
    assert {:ok, nil} == adapter_load(Ecto.TestAdapter, type, nil)
    assert :error == adapter_load(Ecto.TestAdapter, type, 1)

    assert {:ok, %{abc: 1, c: 0, id: @uuid_binary}} ==
           adapter_dump(Ecto.TestAdapter, type, %Schema{id: @uuid_string, a: 1})
    assert {:ok, nil} = adapter_dump(Ecto.TestAdapter, type, nil)
    assert :error = adapter_dump(Ecto.TestAdapter, type, 1)

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
    assert {:ok, nil} = adapter_dump(Ecto.TestAdapter, type, nil)
    assert :error = adapter_dump(Ecto.TestAdapter, type, 1)

    assert cast(type, [%{"abc" => 1}]) == :error
    assert cast(type, [%Schema{}]) == {:ok, [%Schema{}]}
    assert cast(type, []) == {:ok, []}
    assert match?({:array, :any}, type)
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

    test "nil type" do
      assert Ecto.Type.equal?(nil, 1, 1.0)
      refute Ecto.Type.equal?(nil, 1, 2)
    end

    test "bad type" do
      assert_raise ArgumentError, ~r"cannot use :foo as Ecto.Type", fn ->
        Ecto.Type.equal?(:foo, 1, 1.0)
      end
    end
  end

  describe "custom type as primary key" do
    test "autogenerates value" do
      assert {:ok, inserted} = TestRepo.insert(%PrefixedIDSchema{})
      assert "foo-" <> _uuid = inserted.id
    end

    test "custom value" do
      id = "a92f6d0e-52ef-4df8-808b-32d8ef037d48"
      changeset = Ecto.Changeset.cast(%PrefixedIDSchema{}, %{id: id}, [:id])

      assert {:ok, inserted} = TestRepo.insert(changeset)
      assert inserted.id == "foo-" <> id
    end
  end

  defp d(decimal), do: Decimal.new(decimal)

  defp utc(string) do
    string
    |> NaiveDateTime.from_iso8601!()
    |> DateTime.from_naive!("Etc/UTC")
  end
end
