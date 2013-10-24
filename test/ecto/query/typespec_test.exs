defmodule Ecto.Query.TypespecTest do
  use ExUnit.Case, async: true

  alias Ecto.Query.API
  alias Ecto.Query.Typespec

  test "functions" do
    assert API.-(:integer) == { :ok, :integer }
    assert API.-(:float) == { :ok, :float }
    assert { :error, _ } = API.-(:binary)
  end

  test "aliases" do
    assert API.+(:float, :integer) == { :ok, :float }
    assert API.+(:integer, :float) == { :ok, :float }
    assert API.+(:integer, :integer) == { :ok, :integer }
  end

  test "bind var" do
    assert API.==(:binary, :binary) == { :ok, :boolean }
    assert API.==({ :list, :test }, { :list, :test }) == { :ok, :boolean }
    assert { :error, _ } = API.==(:x, :y)

    assert API.in(:apa, { :list, :apa }) == { :ok, :boolean }
    assert API.in(:bapa, { :list, :bapa }) == { :ok, :boolean }
    assert { :error, _ } = API.in(:apa, { :list, :bapa })

    assert API.++({ :list, :apa }, { :list, :apa }) == { :ok, { :list, :apa } }
    assert API.++({ :list, :bapa }, { :list, :bapa }) == { :ok, { :list, :bapa } }
    assert { :error, _ } = API.++({ :list, :apa }, { :list, :bapa })
  end

  test "wildcard" do
    assert API.==(nil, :anything) == { :ok, :boolean }
    assert API.==(:other_thing, nil) == { :ok, :boolean }
    assert API.==({ :list, :integer }, nil) == { :ok, :boolean }

    assert API.count(:test) == { :ok, :integer }
    assert API.count({ :list, :integer }) == { :ok, :integer }
  end

  test "aggregates" do
    assert API.aggregate?(:avg, 1)
    refute API.aggregate?(:avg, 0)
  end
end
