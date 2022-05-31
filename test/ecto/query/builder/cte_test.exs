Code.require_file "../../../support/eval_helpers.exs", __DIR__

defmodule Ecto.Query.Builder.CTETest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.CTE
  doctest Ecto.Query.Builder.CTE

  import Ecto.Query
  import Support.EvalHelpers

  test "fragment CTE" do
    query = "products" |> with_cte("categories", as: fragment("SELECT * FROM categories"))

    assert [{"categories", %Ecto.Query.QueryExpr{expr: expr}}] = query.with_ctes.queries
    assert {:fragment, [], [raw: "SELECT * FROM categories"]} = expr
    refute query.with_ctes.recursive
  end

  test "recursive CTE" do
    initial = "categories" |> where([c], is_nil(c.parent_id))
    recursion = "categories" |> join(:inner, [c], ct in "tree", on: c.parent_id == ct.id)
    tree = initial |> union_all(^recursion)
    query = "products" |> recursive_ctes(true) |> with_cte("tree", as: ^tree)

    assert [{"tree", ^tree}] = query.with_ctes.queries
    assert query.with_ctes.recursive
  end

  test "overrides recursion flag" do
    query = %Ecto.Query{} |> recursive_ctes(true)
    assert query.with_ctes.recursive

    query = query |> recursive_ctes(false)
    refute query.with_ctes.recursive
  end

  test "multiple CTEs" do
    cte1 = from(p in "tbl1")

    query =
      %Ecto.Query{}
      |> with_cte("cte1", as: ^cte1)
      |> with_cte("cte2", as: fragment("SELECT * FROM tbl2"))

    assert [{"cte1", ^cte1}, {"cte2", %Ecto.Query.QueryExpr{expr: expr}}] = query.with_ctes.queries
    assert {:fragment, [], [raw: "SELECT * FROM tbl2"]} = expr
  end

  test "raises on passing a query without ^" do
    assert_raise Ecto.Query.CompileError, ~r"is not a valid CTE", fn ->
      quote_and_eval(%Ecto.Query{} |> with_cte("cte", as: %Ecto.Query{}))
    end
  end

  test "raises on passing a string query without fragment" do
    assert_raise Ecto.Query.CompileError, ~r"is not a valid CTE", fn ->
      quote_and_eval(%Ecto.Query{} |> with_cte("cte", as: "SELECT * FROM tbl"))
    end
  end

  test "overrides existing CTE by name" do
    cte1 = from(p in "tbl1")
    cte2 = from(p in "tbl2")
    query = %Ecto.Query{} |> with_cte("cte", as: ^cte1) |> with_cte("cte", as: ^cte2)

    assert [{"cte", ^cte2}] = query.with_ctes.queries
  end

  test "uses an interpolated CTE name" do
    cte1_name = "cte1"
    cte2_name = "cte2"
    cte1 = from(p in "tbl1")

    query =
      %Ecto.Query{}
      |> with_cte(^cte1_name, as: ^cte1)
      |> with_cte(^cte2_name, as: fragment("SELECT * FROM tbl2"))

    assert [{^cte1_name, ^cte1}, {^cte2_name, %Ecto.Query.QueryExpr{expr: expr}}] = query.with_ctes.queries
    assert {:fragment, [], [raw: "SELECT * FROM tbl2"]} = expr
  end

  defmacro name, do: "cte"
  defmacro query, do: quote(do: fragment("query"))

  test "allows macros on name and query" do
    query = %Ecto.Query{} |> with_cte(name(), as: query())
    assert [{"cte", %Ecto.Query.QueryExpr{expr: expr}}] = query.with_ctes.queries
    assert {:fragment, [], [raw: "query"]} = expr
  end
end
