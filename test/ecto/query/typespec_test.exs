defmodule Ecto.Query.TypespecTest do
  use ExUnit.Case, async: true

  alias Ecto.Query.API

  test "functions" do
    assert API.-(:integer) == {:ok, :integer}
    assert API.-(:float) == {:ok, :float}
    assert {:error, _} = API.-(:binary)
  end

  test "aliases" do
    assert API.+(:float, :integer) == {:ok, :float}
    assert API.+(:integer, :float) == {:ok, :float}
    assert API.+(:integer, :integer) == {:ok, :integer}
  end

  test "bind var" do
    assert API.==(:binary, :binary) == {:ok, :boolean}
    assert API.==({:array, :test}, {:array, :test}) == {:ok, :boolean}
    assert {:error, _} = API.==(:x, :y)

    assert API.in(:apa, {:array, :apa}) == {:ok, :boolean}
    assert API.in(:bapa, {:array, :bapa}) == {:ok, :boolean}
    assert {:error, _} = API.in(:apa, {:array, :bapa})

    assert API.++({:array, :apa}, {:array, :apa}) == {:ok, {:array, :apa}}
    assert API.++({:array, :bapa}, {:array, :bapa}) == {:ok, {:array, :bapa}}
    assert {:error, _} = API.++({:array, :apa}, {:array, :bapa})
  end

  test "wildcard" do
    assert API.==(nil, :anything) == {:ok, :boolean}
    assert API.==(:other_thing, nil) == {:ok, :boolean}
    assert API.==({:array, :integer}, nil) == {:ok, :boolean}

    assert API.count(:test) == {:ok, :integer}
    assert API.count({:array, :integer}) == {:ok, :integer}
  end

  test "aggregates" do
    assert API.aggregate?(:avg, 1)
    refute API.aggregate?(:avg, 0)
  end
end
