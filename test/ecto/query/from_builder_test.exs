defmodule Ecto.Query.FromBuilderTest do
  use Ecto.TestCase, async: true

  import Ecto.Query.FromBuilder

  defmodule MyModel do
    use Ecto.Model
    queryable :my_entity do end
  end

  test "invalid expression" do
    assert_raise Ecto.InvalidQuery, "invalid `from` query expression", fn ->
      escape(quote do 123 in MyModel end)
    end
  end

  test "expressions" do
    assert { [:_], quote do MyModel end } ==
           escape(quote do MyModel end)

    assert { [:p], quote do MyModel end } ==
           escape(quote do p in MyModel end)

    assert { [:p,:q], quote do MyModel end } ==
           escape(quote do [p,q] in MyModel end)

    assert { [:_,:_], quote do abc end } ==
           escape(quote do [_,_] in abc end)

    assert { [], 123 } ==
           escape(123)
  end
end
