Code.require_file "../../../integration_test/support/types.exs", __DIR__

defmodule Ecto.Query.BuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder
  doctest Ecto.Query.Builder

  defp escape(quoted, vars, env) do
    {escaped, {params, _acc}} = escape(quoted, :any, {[], %{}}, vars, env)
    {escaped, params}
  end

  test "escape" do
    assert {Macro.escape(quote do &0.y() end), []} ==
           escape(quote do x.y() end, [x: 0], __ENV__)

    import Kernel, except: [>: 2]
    assert {Macro.escape(quote do &0.y() > &0.z() end), []} ==
           escape(quote do x.y() > x.z() end, [x: 0], __ENV__)

    assert {Macro.escape(quote do &0.y() > &1.z() end), []} ==
           escape(quote do x.y() > y.z() end, [x: 0, y: 1], __ENV__)

    import Kernel, except: [+: 2]
    assert {Macro.escape(quote do &0.y() + &1.z() end), []} ==
           escape(quote do x.y() + y.z() end, [x: 0, y: 1], __ENV__)

    assert {Macro.escape(quote do avg(0) end), []} ==
           escape(quote do avg(0) end, [], __ENV__)

    assert {quote(do: ~s"123"), []} ==
           escape(quote do ~s"123" end, [], __ENV__)

    assert {{:%, [], [Ecto.Query.Tagged, {:%{}, [], [value: {:<<>>, [], [0, 1, 2]}, type: :binary]}]}, []} ==
           escape(quote do <<0,1,2>> end, [], __ENV__)

    assert {:some_atom, []} ==
           escape(quote do :some_atom end, [], __ENV__)

    assert quote(do: &0.z()) ==
           escape(quote do field(x, :z) end, [x: 0], __ENV__)
           |> elem(0)
           |> Code.eval_quoted([], __ENV__)
           |> elem(0)

    assert {Macro.escape(quote do -&0.y() end), []} ==
           escape(quote do -x.y() end, [x: 0], __ENV__)
  end

  test "escape json_extract_path" do
    expected = {Macro.escape(quote do: json_extract_path(&0.y(), ["a", "b"])), []}
    actual = escape(quote do json_extract_path(x.y, ["a", "b"]) end, [x: 0], __ENV__)
    assert actual == expected

    actual = escape(quote do x.y["a"]["b"] end, [x: 0], __ENV__)
    assert actual == expected

    expected = {Macro.escape(quote do: json_extract_path(&0.y(), ["a", 0])), []}
    actual = escape(quote do x.y["a"][0] end, [x: 0], __ENV__)
    assert actual == expected

    expected = {Macro.escape(quote do: json_extract_path(&0.y(), [0, "a"])), []}
    actual = escape(quote do x.y[0]["a"] end, [x: 0], __ENV__)
    assert actual == expected

    assert_raise Ecto.Query.CompileError, "`json_extract_path(x, [\"a\"])` is not a valid query expression", fn ->
      escape(quote do json_extract_path(x, ["a"]) end, [x: 0], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, "`x[\"a\"]` is not a valid query expression", fn ->
      escape(quote do x["a"] end, [x: 0], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r/expected JSON path to contain literal strings.*got: `a`/, fn ->
      escape(quote do x.y[a] end, [x: 0], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, "expected JSON path to be compile-time list, got: `bad`", fn ->
      escape(quote do json_extract_path(x.y, bad) end, [x: 0], __ENV__)
    end
  end

  test "escape fragments" do
    assert {Macro.escape(quote do fragment({:raw, "date_add("}, {:expr, &0.created_at()},
                                           {:raw, ", "}, {:expr, ^0}, {:raw, ")"}) end), [{0, :any}]} ==
      escape(quote do fragment("date_add(?, ?)", p.created_at(), ^0) end, [p: 0], __ENV__)

    assert {Macro.escape(quote do fragment({:raw, ""}, {:expr, ^0}, {:raw, "::text"}) end), [{0, :any}]} ==
      escape(quote do fragment(~S"?::text", ^0) end, [p: 0], __ENV__)

    assert {Macro.escape(quote do fragment({:raw, "query?("}, {:expr, &0.created_at()},
                                           {:raw, ")"}) end), []} ==
      escape(quote do fragment("query\\?(?)", p.created_at()) end, [p: 0], __ENV__)

    assert {Macro.escape(quote do fragment(title: [foo: ^0]) end), [{0, :any}]} ==
      escape(quote do fragment(title: [foo: ^0]) end, [], __ENV__)

    assert_raise Ecto.Query.CompileError, ~r"fragment\(...\) does not allow strings to be interpolated", fn ->
      escape(quote do fragment(:invalid) end, [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError,
                 ~r"expects extra arguments in the same amount of question marks in string. It received 0 extra argument\(s\) but expected 1",
                 fn -> escape(quote do fragment("?") end, [], __ENV__) end

    assert_raise Ecto.Query.CompileError,
                 ~r"expects extra arguments in the same amount of question marks in string. It received 1 extra argument\(s\) but expected 0",
                 fn -> escape(quote do fragment("", 1) end, [], __ENV__) end
  end

  defmacro my_first_value(expr) do
    quote do
      nth_value(unquote(expr), 1)
    end
  end

  test "escape over with window name" do
    assert {Macro.escape(quote(do: over(count(&0.id()), :w))), []}  ==
           escape(quote(do: count(x.id()) |> over(:w)), [x: 0], __ENV__)

    assert {Macro.escape(quote(do: over(nth_value(&0.id(), 1), :w))), []}  ==
           escape(quote(do: nth_value(x.id(), 1) |> over(:w)), [x: 0], __ENV__)

    assert {Macro.escape(quote(do: over(nth_value(&0.id(), 1), :w))), []}  ==
           escape(quote(do: my_first_value(x.id()) |> over(:w)), [x: 0], __ENV__)
  end

  test "escape over with window parts" do
    assert {Macro.escape(quote(do: over(row_number(), []))), []}  ==
           escape(quote(do: over(row_number())), [], __ENV__)

    assert {Macro.escape(quote(do: over(nth_value(&0.id(), 1), []))), []}  ==
           escape(quote(do: over(my_first_value(x.id()))), [x: 0], __ENV__)

    assert {Macro.escape(quote(do: over(nth_value(&0.id(), 1), order_by: [asc: &0.id()]))), []} ==
           escape(quote(do: nth_value(x.id(), 1) |> over(order_by: x.id())), [x: 0], __ENV__)

    assert {Macro.escape(quote(do: over(nth_value(&0.id(), 1), partition_by: [&0.id()]))), []} ==
           escape(quote(do: nth_value(x.id(), 1) |> over(partition_by: x.id())), [x: 0], __ENV__)

    assert {Macro.escape(quote(do: over(nth_value(&0.id(), 1), frame: fragment({:raw, "ROWS"})))), []} ==
           escape(quote(do: nth_value(x.id(), 1) |> over(frame: fragment("ROWS"))), [x: 0], __ENV__)

    assert_raise Ecto.Query.CompileError,
                 ~r"windows definitions given to over/2 do not allow interpolations at the root",
                 fn ->
      escape(quote(do: nth_value(x.id(), 1) |> over(order_by: ^foo)), [x: 0], __ENV__)
    end

    import Kernel, except: [is_nil: 1]
    assert {Macro.escape(quote(do: over(filter(avg(&0.value()), is_nil(&0.flag())), []))), []}  ==
      escape(quote(do: avg(x.value()) |> filter(is_nil(x.flag())) |> over([])), [x: 0], __ENV__)
  end

  test "escape type cast" do
    import Kernel, except: [+: 2]
    assert {Macro.escape(quote do type(&0.y() + &1.z(), :decimal) end), []} ==
           escape(quote do type(x.y() + y.z(), :decimal) end, [x: 0, y: 1], __ENV__)

    assert {Macro.escape(quote do type(&0.y(), :decimal) end), []} ==
          escape(quote do type(field(x, :y), :decimal) end, [x: 0], __ENV__)

    assert {Macro.escape(quote do type(&0.y(), :"Elixir.Ecto.UUID") end), []} ==
          escape(quote do type(field(x, :y), Ecto.UUID) end, [x: 0], __ENV__)

    assert {Macro.escape(quote do type(&0.y(), :"Elixir.Ecto.UUID") end), []} ==
          escape(quote do type(field(x, :y), Ecto.UUID) end, [x: 0], {__ENV__, %{}})

    assert {Macro.escape(quote do type(sum(&0.y()), :decimal) end), []} ==
          escape(quote do type(sum(x.y()), :decimal) end, [x: 0], {__ENV__, %{}})

    assert {Macro.escape(quote do type(count(), :decimal) end), []} ==
          escape(quote do type(count(), :decimal) end, [x: 0], {__ENV__, %{}})

    import Kernel, except: [>: 2]
    assert {Macro.escape(quote do type(filter(sum(&0.y()), &0.y() > &0.z()), :decimal) end), []} ==
          escape(quote do type(filter(sum(x.y()), x.y() > x.z()), :decimal) end, [x: 0], {__ENV__, %{}})

    assert {Macro.escape(quote do type(over(fragment({:raw, "array_agg("}, {:expr, &0.id()}, {:raw, ")"}), :y), {:array, :"Elixir.Ecto.UUID"}) end), []} ==
      escape(quote do type(over(fragment("array_agg(?)", x.id()), :y), {:array, Ecto.UUID}) end, [x: 0], {__ENV__, %{}})
  end

  test "escape parameterized types" do
    parameterized_type = Ecto.ParameterizedType.init(ParameterizedPrefixedString, prefix: "p")
    assert {Macro.escape(quote do type(&0.y(), unquote(parameterized_type)) end), []} ==
          escape(quote do type(field(x, :y), unquote(parameterized_type)) end, [x: 0], __ENV__)
  end

  defmacro wrapped_sum(a) do
    quote do: sum(unquote(a))
  end

  test "escape type cast with macro" do
    assert {Macro.escape(quote do type(sum(&0.y()), :integer) end), []} ==
          escape(quote do type(wrapped_sum(x.y()), :integer) end, [x: 0], __ENV__)
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
    assert_raise Ecto.Query.CompileError, ~r"is not a valid query expression. Only literal binaries and strings are allowed", fn ->
      escape(quote(do: "#{x}"), [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r"short-circuit operators are not supported: `&&`", fn ->
      escape(quote(do: true && false), [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r"`1 = 1` is not a valid query expression. The match operator is not supported: `=`", fn ->
      escape(quote(do: 1 = 1), [], __ENV__)
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

    assert_raise Ecto.Query.CompileError, ~r"expected literal atom or interpolated value.*got: `var`", fn ->
      escape(quote(do: field(x, var)), [x: 0], __ENV__) |> elem(0) |> Code.eval_quoted([], __ENV__)
    end

    assert_raise Ecto.Query.CompileError,
                 ~r"make sure that you have required\n  the module or imported the relevant function",
                 fn ->
      escape(quote(do: Foo.bar(x)), [x: 0], __ENV__) |> elem(0) |> Code.eval_quoted([], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r"unknown window function lag/0", fn ->
      escape(quote(do: over(lag())), [], __ENV__)
    end
  end

  test "doesn't escape interpolation" do
    import Kernel, except: [>: 2, ++: 2]
    assert {Macro.escape(quote(do: ^0)), [{quote(do: 1 > 2), :any}]} ==
           escape(quote(do: ^(1 > 2)), [], __ENV__)

    assert {Macro.escape(quote(do: ^0)), [{quote(do: [] ++ []), :any}]} ==
           escape(quote(do: ^([] ++ [])), [], __ENV__)
  end

  defp params(quoted, type, vars \\ []) do
    {_, {params, _acc}} = escape(quoted, type, {[], %{}}, vars, __ENV__)
    params
  end

  test "infers the type for parameter" do
    assert [{_, :integer}] =
           params(quote(do: ^1 == 2), :any)

    assert [{_, :integer}] =
           params(quote(do: 2 == ^1), :any)

    assert [{_, :any}, {_, :any}] =
           params(quote(do: ^1 == ^2), :any)

    assert [{_, {0, :title}}] =
           params(quote(do: ^1 == p.title), :any, [p: 0])

    assert [{_, :boolean}] =
           params(quote(do: ^1 and true), :any)

    assert [{_, :boolean}] =
           params(quote(do: ^1), :boolean)
  end

  test "returns the type for quoted query expression" do
    assert quoted_type({:type, [], ["foo", :hello]}, []) == :hello

    assert quoted_type(1, []) == :integer
    assert quoted_type(1.0, []) == :float
    assert quoted_type("foo", []) == :string
    assert quoted_type(true, []) == :boolean
    assert quoted_type(false, []) == :boolean
    assert quoted_type(nil, []) == :any
    assert quoted_type(:some_atom, []) == :atom

    assert quoted_type([1, 2, 3], []) == {:array, :integer}
    assert quoted_type([1, 2.0, 3], []) == {:array, :any}

    assert quoted_type({:sigil_w, [], ["foo", []]}, []) == {:array, :string}
    assert quoted_type({:sigil_s, [], ["foo", []]}, []) == :string

    assert quoted_type({:==, [], [1, 2]}, []) == :boolean
    assert quoted_type({:like, [], [1, 2]}, []) == :boolean
    assert quoted_type({:and, [], [1, 2]}, []) == :boolean
    assert quoted_type({:or, [], [1, 2]}, []) == :boolean
    assert quoted_type({:not, [], [1]}, []) == :boolean

    assert quoted_type({:count, [], [1]}, []) == :integer
    assert quoted_type({:count, [], []}, []) == :integer
    assert quoted_type({:max, [], [1]}, []) == :integer
    assert quoted_type({:avg, [], [1]}, []) == :any

    assert quoted_type({{:., [], [{:p, [], Elixir}, :title]}, [], []}, [p: 0]) == {0, :title}
    assert quoted_type({:field, [], [{:p, [], Elixir}, :title]}, [p: 0]) == {0, :title}
    assert quoted_type({:field, [], [{:p, [], Elixir}, {:^, [], [:title]}]}, [p: 0]) == {0, :title}

    assert quoted_type({:unknown, [], []}, []) == :any
  end

  test "validate_type!" do
    env = {__ENV__, :ok}

    assert validate_type!({:array, :string}, [], env) == {:array, :string}
    assert validate_type!(quote do ^:string end, [], env) == :string
    assert validate_type!(quote do Ecto.UUID end, [], env) == Ecto.UUID
    assert validate_type!(quote do :string end, [], env) == :string
    assert validate_type!(quote do x.title end, [x: 0], env) == {0, :title}
    assert validate_type!(quote do field(x, :title) end, [x: 0], env) == {0, :title}

    assert_raise Ecto.Query.CompileError, ~r"^type/2 expects an alias, atom", fn ->
      validate_type!(quote do "string" end, [x: 0], env)
    end
  end
end
