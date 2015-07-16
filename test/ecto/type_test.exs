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

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "" do
      field :a, :integer
    end

    def changeset(params, model) do
      Ecto.Changeset.cast(model, params, ~w(a))
    end
  end

  import Kernel, except: [match?: 2], warn: false
  import Ecto.Type
  doctest Ecto.Type

  test "custom types" do
    assert load(Custom, "foo", %{}) == {:ok, :load}
    assert dump(Custom, "foo", %{}) == {:ok, :dump}
    assert cast(Custom, "foo", %{}) == {:ok, :cast}

    assert load(Custom, nil, %{}) == {:ok, nil}
    assert dump(Custom, nil, %{}) == {:ok, %Ecto.Query.Tagged{type: :custom, value: nil}}
    assert cast(Custom, nil, %{}) == {:ok, nil}
  end

  test "boolean types" do
    assert load(:boolean, 1, %{}) == {:ok, true}
    assert load(:boolean, 0, %{}) == {:ok, false}
  end

  test "map types" do
    assert load(:map, "{\"a\": 1}", %{}) == {:ok, %{"a" => 1}}
    assert load(:map, %{"a" => 1}, %{}) == {:ok, %{"a" => 1}}
    assert load(:map, 1, %{}) == :error

    assert dump(:map, %{a: 1}, %{}) == {:ok, %{a: 1}}
    assert dump(:map, 1, %{}) == :error
  end

  test "embeds_one" do
    type = {:embed, Ecto.Embedded.struct(__MODULE__, :embed, cardinality: :one,
                                         embed: Model, on_cast: :changeset)}
    id_types = %{binary_id: :string}
    assert {:ok, %Model{a: 1}} = load(type, %{"a" => 1}, id_types)
    assert {:ok, %Model{a: 1}} = load(type, "{\"a\": 1}", id_types)
    assert :error == load(type, 1, id_types)

    assert {:ok, %{a: 1, id: %{value: nil}}} = dump(type, %Model{a: 1}, id_types)
    assert :error == dump(type, 1, id_types)

    assert %Model{a: 1} = cast(type, %{"a" => 1}, %{})
    assert :error == cast(type, %{}, %{})
    assert :error == cast(type, 1, %{})
  end

  test "embeds_many with array" do
    type = {:embed, Ecto.Embedded.struct(__MODULE__, :embed,
                                         cardinality: :many, container: :array,
                                         embed: Model, on_cast: :changeset)}
    id_types = %{binary_id: :string}
    assert {:ok, [%Model{a: 1}]} = load(type, [%{"a" => 1}], id_types)
    assert {:ok, [%Model{a: 1}]} = load(type, ["{\"a\": 1}"], id_types)
    assert :error == load(type, 1, id_types)

    assert {:ok, [%{a: 1, id: "a"}]} = dump(type, [%Model{a: 1, id: "a"}], id_types)
    assert :error == dump(type, 1, id_types)

    assert [%Model{a: 1}] = cast(type, [%{"a" => 1}], %{})
    assert :error == cast(type, [%{}], %{})
    assert :error == cast(type, [[]], %{})
  end

  test "custom types with array" do
    assert load({:array, Custom}, ["foo"], %{}) == {:ok, [:load]}
    assert dump({:array, Custom}, ["foo"], %{}) == {:ok, [:dump]}
    assert cast({:array, Custom}, ["foo"], %{}) == {:ok, [:cast]}

    assert load({:array, Custom}, [nil], %{}) == {:ok, [nil]}
    assert dump({:array, Custom}, [nil], %{}) == {:ok, %Ecto.Query.Tagged{type: {:array, :custom}, value: [nil]}}
    assert cast({:array, Custom}, [nil], %{}) == {:ok, [nil]}

    assert load({:array, Custom}, 1, %{}) == :error
    assert dump({:array, Custom}, 1, %{}) == :error
    assert cast({:array, Custom}, 1, %{}) == :error
  end

  test "decimal casting" do
    assert cast(:decimal, "1.0", %{}) == {:ok, Decimal.new("1.0")}
    assert cast(:decimal, 1.0, %{}) == {:ok, Decimal.new("1.0")}
    assert cast(:decimal, 1, %{}) == {:ok, Decimal.new("1")}
  end
end
