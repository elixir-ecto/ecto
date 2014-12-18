defmodule Ecto.Query.Builder.OrderByTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.OrderBy
  doctest Ecto.Query.Builder.OrderBy

  test "escape" do
    assert {Macro.escape(quote do [asc: &0.y] end), %{}} ==
           escape(quote do x.y end, [x: 0])

    assert {Macro.escape(quote do [asc: &0.x, asc: &1.y] end), %{}} ==
           escape(quote do [x.x, y.y] end, [x: 0, y: 1])

    assert {Macro.escape(quote do [asc: &0.x, desc: &1.y] end), %{}} ==
           escape(quote do [asc: x.x, desc: y.y] end, [x: 0, y: 1])

    assert {Macro.escape(quote do [asc: 1 == 2] end), %{}} ==
           escape(quote do 1 == 2 end, [])

    comp = Macro.escape(quote do: 1 == 2)
    assert {quote do [{unquote(Ecto.Query.Builder.OrderBy).dir!(foo), unquote(comp)}] end, %{}} ==
           escape(quote do [{^foo, 1 == 2}] end, [])
  end

  test "escape raise" do
    assert_raise Ecto.QueryError, "unbound variable `x` in query", fn ->
      escape(quote do x.y end, [])
    end

    message = "expected :asc, :desc or interpolated value in order by, got: `:test`"
    assert_raise Ecto.QueryError, message, fn ->
      escape(quote do [test: x.y] end, [x: 0])
    end

    assert_raise Ecto.QueryError, ~r"expected :asc or :desc in order by, got: `:temp`", fn ->
      escape(quote do [{^var!(temp), x.y}] end, [x: 0])
      |> elem(0)
      |> Code.eval_quoted([temp: :temp], __ENV__)
    end
  end
end
