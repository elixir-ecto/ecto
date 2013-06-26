Code.require_file "../../test_helper.exs", __DIR__

defmodule Ecto.Query.FromBuilderTest do
  use ExUnit.Case

  import Ecto.Query.FromBuilder

  test "escape" do
    assert { :x, quote do X end } ==
           escape(quote do x in X end)

    assert { :x, quote do X.Y.Z end } ==
           escape(quote do x in X.Y.Z end)
  end

  test "escape raise" do
    message = "only `in` expressions binding variables to records allowed in from expressions"

    assert_raise ArgumentError, message, fn ->
      escape(quote do 1 end)
    end

    assert_raise ArgumentError, message, fn ->
      escape(quote do f() end)
    end

    assert_raise ArgumentError, message, fn ->
      escape(quote do x end)
    end

    assert_raise ArgumentError, message, fn ->
      escape(quote do x in y end)
    end
  end
end
