defmodule Ecto.Query.BuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder
  doctest Ecto.Query.Builder

  defp escape(quoted, vars) do
    escape(quoted, :any, %{}, vars)
  end

  test "escape" do
    assert {Macro.escape(quote do &0.y end), %{}} ==
           escape(quote do x.y end, [x: 0])

    assert {Macro.escape(quote do &0.y == &0.z end), %{}} ==
           escape(quote do x.y == x.z end, [x: 0])

    assert {Macro.escape(quote do &0.y == &1.z end), %{}} ==
           escape(quote do x.y == y.z end, [x: 0, y: 1])

    assert {Macro.escape(quote do avg(0) end), %{}} ==
           escape(quote do avg(0) end, [])

    assert {Macro.escape(quote do fragment("date_add(", &0.created_at, ", ", ^0, ")") end), %{0 => {0, :any}}} ==
           escape(quote do fragment("date_add(?, ?)", p.created_at, ^0) end, [p: 0])

    assert {quote(do: ~s"123"), %{}} ==
           escape(quote do ~s"123" end, [])

    assert {{:%, [], [Ecto.Query.Tagged, {:%{}, [], [value: "abc", type: :uuid]}]}, %{}} ==
           escape(quote do uuid("abc") end, [])

    assert quote(do: &0.z) ==
           escape(quote do field(x, :z) end, [x: 0]) |> elem(0) |> Code.eval_quoted([], __ENV__) |> elem(0)
  end

  test "escape type checks" do
    assert_raise Ecto.Query.CompileError, ~r"It returns a value of type :boolean but a value of type :integer is expected", fn ->
      escape(quote(do: ^1 == ^2), :integer, %{}, [])
    end

    assert_raise Ecto.Query.CompileError, ~r"It returns a value of type :boolean but a value of type :integer is expected", fn ->
      escape(quote(do: 1 > 2), :integer, %{}, [])
    end
  end

  test "escape raise" do
    assert_raise Ecto.Query.CompileError, ~r"variable `x` is not a valid query expression", fn ->
      escape(quote(do: x), [])
    end

    assert_raise Ecto.Query.CompileError, ~r"`:atom` is not a valid query expression", fn ->
      escape(quote(do: :atom), [])
    end

    assert_raise Ecto.Query.CompileError, ~r"`unknown\(1, 2\)` is not a valid query expression", fn ->
      escape(quote(do: unknown(1, 2)), [])
    end

    assert_raise Ecto.Query.CompileError, ~r"unbound variable", fn ->
      escape(quote(do: x.y), [])
    end

    assert_raise Ecto.Query.CompileError, ~r"unbound variable", fn ->
      escape(quote(do: x.y == 1), [])
    end

    assert_raise Ecto.Query.CompileError, ~r"expected literal atom or interpolated value", fn ->
      escape(quote(do: field(x, 123)), [x: 0]) |> elem(0) |> Code.eval_quoted([], __ENV__)
    end
  end

  test "doesn't escape interpolation" do
    assert {Macro.escape(quote(do: ^0)), %{0 => {quote(do: 1 == 2), :any}}} ==
           escape(quote(do: ^(1 == 2)), [])

    assert {Macro.escape(quote(do: ^0)), %{0 => {quote(do: [] ++ []), :any}}} ==
           escape(quote(do: ^([] ++ [])), [])

    assert {Macro.escape(quote(do: ^0 == ^1)), %{0 => {1, :any}, 1 => {2, :any}}} ==
           escape(quote(do: ^1 == ^2), [])
  end

  defp params(quoted, type, vars \\ []) do
    escape(quoted, type, %{}, vars) |> elem(1)
  end

  test "infers the type for parameter" do
    assert params(quote(do: ^1 == 2), :any) ==
           %{0 => {1, :integer}}

    assert params(quote(do: 2 == ^1), :any) ==
           %{0 => {1, :integer}}

    assert params(quote(do: ^1 == ^2), :any) ==
           %{0 => {1, :any}, 1 => {2, :any}}

    assert params(quote(do: ^1 == p.title), :any, [p: 0]) ==
           %{0 => {1, {0, :title}}}

    assert params(quote(do: ^1 and true), :any) ==
           %{0 => {1, :boolean}}

    assert params(quote(do: ^1), :boolean) ==
           %{0 => {1, :boolean}}
  end

  test "returns the type for quoted query expression" do
    assert quoted_type({:<<>>, [], [1, 2, 3]}, []) == :binary
    assert quoted_type({:type, [], ["foo", :hello]}, []) == :hello

    assert quoted_type(1, []) == :integer
    assert quoted_type(1.0, []) == :float
    assert quoted_type("foo", []) == :string
    assert quoted_type(true, []) == :boolean
    assert quoted_type(false, []) == :boolean

    assert quoted_type([1, 2, 3], []) == {:array, :integer}
    assert quoted_type([1, 2.0, 3], []) == {:array, :any}

    assert quoted_type({:sigil_w, [], ["foo", []]}, []) == {:array, :string}
    assert quoted_type({:sigil_s, [], ["foo", []]}, []) == :string

    assert quoted_type({:==, [], [1, 2]}, []) == :boolean
    assert quoted_type({:like, [], [1, 2]}, []) == :boolean
    assert quoted_type({:and, [], [1, 2]}, []) == :boolean
    assert quoted_type({:or, [], [1, 2]}, []) == :boolean
    assert quoted_type({:not, [], [1]}, []) == :boolean
    assert quoted_type({:avg, [], [1]}, []) == :any

    assert quoted_type({{:., [], [{:p, [], Elixir}, :title]}, [], []}, [p: 0]) == {0, :title}
    assert quoted_type({:field, [], [{:p, [], Elixir}, :title]}, [p: 0]) == {0, :title}
    assert quoted_type({:field, [], [{:p, [], Elixir}, {:^, [], [:title]}]}, [p: 0]) == {0, :title}

    assert quoted_type({:unknown, [], []}, []) == :any
  end
end
