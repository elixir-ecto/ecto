defmodule Ecto.Query.FromBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.FromBuilder

  defmodule MyEntity do
    use Ecto.Entity
    dataset :my_entity do end
  end

  test "invalid expression" do
    assert_raise Ecto.InvalidQuery, "invalid `from` query expression", fn ->
      escape(quote do 123 in MyEntity end)
    end
  end

  test "expressions" do
    assert { [:_], quote do MyEntity end } ==
           escape(quote do MyEntity end)

    assert { [:p], quote do MyEntity end } ==
           escape(quote do p in MyEntity end)

    assert { [:p,:q], quote do MyEntity end } ==
           escape(quote do [p,q] in MyEntity end)

    assert { [], 123 } ==
           escape(123)
  end
end
