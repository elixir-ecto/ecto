defmodule Ecto.Model.QueryableTest do
  use ExUnit.Case, async: true

  defmodule User do
    use Ecto.Model.Queryable

    queryable "users" do
      # Type defaults to string
      field :name
    end

    def test_attr(:entity), do: @ecto_entity
    def test_attr(:source), do: @ecto_source

    def from_1 do
      from(c in __MODULE__)
    end

    def from_2 do
      from(c in __MODULE__, where: c.name == nil)
    end
  end

  test "imports Ecto.Query functions" do
    assert User.from_1 == User
    assert is_record(User.from_2, Ecto.Query.Query)
  end

  test "delegates to the given entity" do
    assert is_record(User.new, User.Entity)
    assert is_record(User.new(name: "jose"), User.Entity)
  end

  test "queryable attributes" do
    assert User.test_attr(:entity) == User.Entity
    assert User.test_attr(:source) == "users"
  end

  test "generated model functions" do
    assert User.__model__(:entity) == User.Entity
    assert User.__model__(:source) == "users"
  end
end
