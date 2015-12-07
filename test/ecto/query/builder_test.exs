defmodule Ecto.Query.BuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder
  doctest Ecto.Query.Builder

  defp escape(quoted, vars, env) do
    escape(quoted, :any, %{}, vars, env)
  end

  test "escape" do
    assert {Macro.escape(quote do &0.y end), %{}} ==
           escape(quote do x.y end, [x: 0], __ENV__)

    import Kernel, except: [>: 2]
    assert {Macro.escape(quote do &0.y > &0.z end), %{}} ==
           escape(quote do x.y > x.z end, [x: 0], __ENV__)

    assert {Macro.escape(quote do &0.y > &1.z end), %{}} ==
           escape(quote do x.y > y.z end, [x: 0, y: 1], __ENV__)

    assert {Macro.escape(quote do avg(0) end), %{}} ==
           escape(quote do avg(0) end, [], __ENV__)

    assert {quote(do: ~s"123"), %{}} ==
           escape(quote do ~s"123" end, [], __ENV__)

    assert {{:%, [], [Ecto.Query.Tagged, {:%{}, [], [value: {:<<>>, [], [0, 1, 2]}, type: :binary]}]}, %{}} ==
           escape(quote do <<0,1,2>> end, [], __ENV__)

    assert quote(do: &0.z) ==
           escape(quote do field(x, :z) end, [x: 0], __ENV__)
           |> elem(0)
           |> Code.eval_quoted([], __ENV__)
           |> elem(0)
  end

  test "escape fragments" do
    assert {Macro.escape(quote do fragment({:raw, "date_add("}, {:expr, &0.created_at},
                                           {:raw, ", "}, {:expr, ^0}, {:raw, ")"}) end), %{0 => {0, :any}}} ==
      escape(quote do fragment("date_add(?, ?)", p.created_at, ^0) end, [p: 0], __ENV__)

    assert {Macro.escape(quote do fragment({:raw, "query?("}, {:expr, &0.created_at},
                                           {:raw, ")"}) end), %{}} ==
      escape(quote do fragment("query\\?(?)", p.created_at) end, [p: 0], __ENV__)

    assert {Macro.escape(quote do fragment(title: [foo: ^0]) end), %{0 => {0, :any}}} ==
      escape(quote do fragment(title: [foo: ^0]) end, [], __ENV__)

    assert_raise Ecto.Query.CompileError, ~r"expects the first argument to be .* got: `:invalid`", fn ->
      escape(quote do fragment(:invalid) end, [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r"expects extra arguments in the same amount of question marks in string", fn ->
      escape(quote do fragment("?") end, [], __ENV__)
    end
  end

  test "escape type checks" do
    assert_raise Ecto.Query.CompileError, ~r"It returns a value of type :boolean but a value of type :integer is expected", fn ->
      escape(quote(do: ^1 == ^2), :integer, %{}, [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r"It returns a value of type :boolean but a value of type :integer is expected", fn ->
      escape(quote(do: 1 > 2), :integer, %{}, [], __ENV__)
    end
  end

  test "escape raise" do
    assert_raise Ecto.Query.CompileError, ~r"variable `x` is not a valid query expression", fn ->
      escape(quote(do: x), [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r"is not a valid query expression. Only literal binaries and strings are allowed", fn ->
      escape(quote(do: "#{x}"), [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r"`:atom` is not a valid query expression", fn ->
      escape(quote(do: :atom), [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r"`unknown\(1, 2\)` is not a valid query expression", fn ->
      escape(quote(do: unknown(1, 2)), [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r"unbound variable", fn ->
      escape(quote(do: x.y), [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r"unbound variable", fn ->
      escape(quote(do: x.y == 1), [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r"expected literal atom or interpolated value", fn ->
      escape(quote(do: field(x, 123)), [x: 0], __ENV__) |> elem(0) |> Code.eval_quoted([], __ENV__)
    end
  end

  test "doesn't escape interpolation" do
    import Kernel, except: [>: 2, ++: 2]
    assert {Macro.escape(quote(do: ^0)), %{0 => {quote(do: 1 > 2), :any}}} ==
           escape(quote(do: ^(1 > 2)), [], __ENV__)

    assert {Macro.escape(quote(do: ^0)), %{0 => {quote(do: [] ++ []), :any}}} ==
           escape(quote(do: ^([] ++ [])), [], __ENV__)

    assert {Macro.escape(quote(do: ^0 > ^1)), %{0 => {1, :any}, 1 => {2, :any}}} ==
           escape(quote(do: ^1 > ^2), [], __ENV__)
  end

  defp params(quoted, type, vars \\ []) do
    escape(quoted, type, %{}, vars, __ENV__) |> elem(1)
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
