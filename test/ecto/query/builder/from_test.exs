Code.require_file("../../../support/eval_helpers.exs", __DIR__)

defmodule Ecto.Query.Builder.FromTest do
  use ExUnit.Case, async: true
  import Ecto.Query.Builder.From
  import Support.EvalHelpers
  doctest Ecto.Query.Builder.From

  import Ecto.Query

  defmodule Schema do
    use Ecto.Schema

    schema "schema" do
      field :num, :integer
      field :text, :string
    end
  end

  defmacro from_macro(left, right) do
    quote do
      fragment("? <> ?", unquote(left), unquote(right))
    end
  end

  defmacro jsonb_to_recordset(data, columns) do
    quote do
      fragment("jsonb_to_recordset(?)", unquote(data))
      |> with_columns(unquote(columns))
    end
  end

  test "expands macros as sources" do
    right = "right"

    assert %Ecto.Query.FromExpr{source: {:fragment, [], _}, params: [{"right", :any}]} =
             from(p in from_macro("left", ^right)).from
  end

  test "values list source" do
    values = [%{num: 1, text: "one"}, %{num: 2, text: "two"}]
    types = %{num: :integer, text: :string}
    query = from(v in values(values, types))

    types_kw = Enum.map(types, & &1)
    assert query.from.source == {:values, [], [types_kw, length(values)]}
  end

  test "values list source with types defined by schema" do
    values = [%{num: 1, text: "one"}, %{num: 2, text: "two"}]
    type_schema = Schema
    types_kw = Enum.map(%{num: :integer, text: :string}, & &1)
    query = from(v in values(values, type_schema))

    assert query.from.source == {:values, [], [types_kw, length(values)]}
  end

  test "values list source with empty values" do
    msg = "must provide a non-empty list to values/2"

    assert_raise ArgumentError, msg, fn ->
      from(v in values(Process.get(:unused, []), %{}))
    end
  end

  test "values list source with missing types" do
    msg =
      "values/2 must declare the type for every field. The type was not given for field `text`"

    assert_raise ArgumentError, msg, fn ->
      values = [%{num: 1, text: "one"}, %{num: 2, text: "two"}]
      types = %{num: :integer}
      from(v in values(values, types))
    end
  end

  test "values list source with missing schema types" do
    msg =
      "values/2 must declare the type for every field. The type was not given for field `not_a_field`"

    assert_raise ArgumentError, msg, fn ->
      values = [%{not_a_field: 1}]
      types = Schema
      from(v in values(values, types))
    end
  end

  test "values list source with inconsistent fields across entries" do
    # Missing field
    msg =
      "each member of a values list must have the same fields. Missing field `text` in %{num: 2}"

    assert_raise ArgumentError, msg, fn ->
      values = [%{num: 1, text: "one"}, %{num: 2}]
      types = %{num: :integer, text: :string}
      from(v in values(values, types))
    end
  end

  test "add column names to fragment sources with with_columns/2" do
    data = [%{a: 1, b: "foo"}, %{a: 2, b: "bar"}]
    q = from(j in jsonb_to_recordset(^data, [:a, :b]))
    assert %{source: {:fragment, [column_names: [:a, :b]], _}} = q.from
  end

  test "add interpolated column names to fragment sources with with_columns/2" do
    columns = [:a, :b]
    data = [%{a: 1, b: "foo"}, %{a: 2, b: "bar"}]
    q = from(j in jsonb_to_recordset(^data, ^columns))
    assert %{source: {:fragment, [column_names: ^columns], _}} = q.from
  end

  test "with_columns/2 raises when not given a fragment" do
    msg = ~r/must have a fragment as a first argument/

    assert_raise Ecto.Query.CompileError, msg, fn->
      quote_and_eval(from(p in with_columns(Post, [:a, :b])))
    end 
  end

  test "with_columns/2 raises when not given a list of atoms" do
    msg = ~r/expected a list of atoms/

    assert_raise Ecto.Query.CompileError, msg, fn->
      quote_and_eval(from(j in jsonb_to_recordset(^[%{a: 1, b: "foo"}], ["a", "b"])))
    end 
  end
end
