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
      field :a, :integer
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

  test "data type protocol" do
    defmodule Name do
      defstruct first: "", last: ""
    end

    name = struct(Name, first: "john", last: "doe")
    assert cast(:string, name) == :error
    assert cast(:integer, name) == :error

    defimpl Ecto.DataType, for: Name do
      def cast(%Name{first: first, last: last}, :string) do
        {:ok, first <> " " <> last}
      end
      def cast(_, _) do
        :error
      end
      def dump(%Name{first: first, last: last}) do
        {:ok, first <> " " <> last}
      end
    end

    assert cast(:string, name) == {:ok, "john doe"}
    assert cast(:integer, name) == :error
  end

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

  test "decimal casting" do
    assert cast(:decimal, "1.0") == {:ok, Decimal.new("1.0")}
    assert cast(:decimal, 1.0) == {:ok, Decimal.new("1.0")}
    assert cast(:decimal, 1) == {:ok, Decimal.new("1")}
  end

  @uuid_string "bfe0888c-5c59-4bb3-adfd-71f0b85d3db7"
  @uuid_binary <<191, 224, 136, 140, 92, 89, 75, 179, 173, 253, 113, 240, 184, 93, 61, 183>>

  test "embeds_one" do
    embed = %Ecto.Embedded{field: :embed, cardinality: :one,
                           owner: __MODULE__, related: Schema}
    type  = {:embed, embed}

    assert {:ok, %Schema{a: 1, c: 0}} = adapter_load(Ecto.TestAdapter, type, %{"a" => 1})
    assert {:ok, nil} == adapter_load(Ecto.TestAdapter,type, nil)
    assert :error == adapter_load(Ecto.TestAdapter, type, 1)

    assert {:ok, %{a: 1, c: 0, id: @uuid_binary}} ==
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

    assert {:ok, [%Schema{a: 1, c: 0}]} = adapter_load(Ecto.TestAdapter, type, [%{"a" => 1}])
    assert {:ok, []} == adapter_load(Ecto.TestAdapter, type, nil)
    assert :error == adapter_load(Ecto.TestAdapter, type, 1)

    assert {:ok, [%{a: 1, id: @uuid_binary, c: 0}]} ==
           adapter_dump(Ecto.TestAdapter, type, [%Schema{id: @uuid_string, a: 1}])

    assert cast(type, [%{"a" => 1}]) == :error
    assert cast(type, [%Schema{}]) == {:ok, [%Schema{}]}
    assert cast(type, []) == {:ok, []}
    assert match?({:array, :any}, type)
  end
end
