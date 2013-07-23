Code.require_file "../../test_helper.exs", __DIR__

defmodule Ecto.Query.FromBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.FromBuilder

  defmodule MyEntity do
    use Ecto.Entity
    dataset :my_entity do end
  end

  test "escape" do
    assert { :x, MyEntity } ==
           escape(quote do x in MyEntity end, [], __ENV__)

    assert { :x, MyEntity } ==
           escape(quote do x in Elixir.Ecto.Query.FromBuilderTest.MyEntity end, [], __ENV__)
  end

  test "escape raise" do
    message = %r"only `in` expressions binding variables to entities are allowed"

    assert_raise Ecto.InvalidQuery, message, fn ->
      escape(quote do 1 end, [], __ENV__)
    end

    assert_raise Ecto.InvalidQuery, message, fn ->
      escape(quote do f() end, [], __ENV__)
    end

    assert_raise Ecto.InvalidQuery, message, fn ->
      escape(quote do x end, [], __ENV__)
    end

    assert_raise Ecto.InvalidQuery, message, fn ->
      escape(quote do x in y end, [], __ENV__)
    end

    assert_raise Ecto.InvalidQuery, %r"`NotAnEntity` is not an Ecto entity", fn ->
      escape(quote do p in NotAnEntity end, [], __ENV__)
    end

    assert_raise Ecto.InvalidQuery, "variable `x` is already defined in query", fn ->
      escape(quote do x in MyEntity end, [:x], __ENV__)
    end
  end
end
