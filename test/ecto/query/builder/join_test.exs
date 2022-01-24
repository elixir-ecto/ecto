Code.require_file "../../../support/eval_helpers.exs", __DIR__

defmodule Ecto.Query.Builder.JoinTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Join
  import Support.EvalHelpers
  doctest Ecto.Query.Builder.Join

  import Ecto.Query

  defmacro join_macro(left, right) do
    quote do
      fragment("? <> ?", unquote(left), unquote(right))
    end
  end

  test "expands macros as sources" do
    left = "left"
    right = "right"
    assert %{joins: [_]} = join("posts", :inner, [p], c in join_macro(^left, ^right), on: true)
  end

  test "accepts keywords on :on" do
    assert %{joins: [join]} =
            join("posts", :inner, [p], c in "comments", on: [post_id: p.id, public: true])
    assert Macro.to_string(join.on.expr) ==
           "&1.post_id() == &0.id() and &1.public() == %Ecto.Query.Tagged{tag: nil, type: {1, :public}, value: true}"
    assert join.on.params == []
  end

  test "accepts queries on interpolation" do
    qual = :left
    source = "comments"
    assert %{joins: [%{source: {"comments", nil}}]} =
            join("posts", qual, [p], c in ^source, on: true)

    qual = :right
    source = Comment
    assert %{joins: [%{source: {nil, Comment}}]} =
            join("posts", qual, [p], c in ^source, on: true)

    qual = :right
    source = {"user_comments", Comment}
    assert %{joins: [%{source: {"user_comments", Comment}}]} =
            join("posts", qual, [p], c in ^source, on: true)

    qual = :inner
    source = from c in "comments", where: c.public
    assert %{joins: [%{source: %Ecto.Query{from: %{source: {"comments", nil}}}}]} =
            join("posts", qual, [p], c in ^source, on: true)
  end

  test "accepts interpolation on :on" do
    assert %{joins: [join]} =
            join("posts", :inner, [p], "comments", on: [post_id: ^1])
    assert Macro.to_string(join.on.expr) == "&1.post_id() == ^0"
    assert join.on.params == [{1, {1, :post_id}}]

    assert %{joins: [join]} =
            join("posts", :inner, [p], c in "comments", on: ^[post_id: 1, public: true])
    assert Macro.to_string(join.on.expr) == "&1.post_id() == ^0 and &1.public() == ^1"
    assert join.on.params == [{1, {1, :post_id}}, {true, {1, :public}}]

    dynamic = dynamic([p, c], c.post_id == p.id and c.public == ^true)
    assert %{joins: [join]} =
            join("posts", :inner, [p], c in "comments", on: ^dynamic)
    assert Macro.to_string(join.on.expr) == "&1.post_id() == &0.id() and &1.public() == ^0"
    assert join.on.params == [{true, {1, :public}}]
  end

  test "accepts interpolation on assoc/2 field" do
    assoc = :comments
    join("posts", :left, [p], c in assoc(p, ^assoc), on: true)
  end

  test "accepts subqueries" do
    subquery = "comments"
    join("posts", :left, [p], c in subquery(subquery), on: true)
    join("posts", :left, [p], c in subquery(subquery, prefix: "sample"), on: true)
  end
  
  test "`as` accepts literal atoms and interpolated values, but not other literals" do
    name = :comments
    join("posts", :left, [p], c in assoc(p, :comments), as: :comments)
    join("posts", :left, [p], c in assoc(p, :comments), as: ^name)
    assert_raise Ecto.Query.CompileError, "`as` must be a compile time atom or an interpolated value using ^, got: 10", fn -> 
      quote_and_eval(join("posts", :left, [p], c in assoc(p, :comments), as: 10))
    end
  end

  test "raises on invalid qualifier" do
    assert_raise ArgumentError,
                 ~r/invalid join qualifier `:whatever`/, fn ->
      qual = :whatever
      join("posts", qual, [p], c in "comments", on: true)
    end
  end

  test "raises on invalid interpolation" do
    assert_raise Protocol.UndefinedError, fn ->
      source = 123
      join("posts", :left, [p], c in ^source, on: true)
    end
  end

  test "raises on invalid expressions on :on" do
    assert_raise ArgumentError, ~r/invalid expression for join `:on`/, fn ->
      escape(quote do
        join("posts", :inner, [p], c in "comments", on: p.id in subquery("posts"))
      end, [], __ENV__)
    end

    assert_raise ArgumentError, ~r/invalid expression for join `:on`/, fn ->
      escape(quote do
        join("posts", :inner, [p], c in "comments", on: exists(p.id))
      end, [], __ENV__)
    end
  end

  test "raises on invalid assoc/2" do
    assert_raise Ecto.Query.CompileError,
                 ~r/you passed the variable \`field_var\` to \`assoc\/2\`/, fn ->
      escape(quote do assoc(join_var, field_var) end, nil, nil)
    end
  end

  test "raises on mix of valid and invalid options passed to join/5" do
    assert_raise ArgumentError, ~r/invalid option `foo` passed/, fn ->
      escape(quote do
        join("posts", :left, [p], c in "comments", on: true, foo: :bar)
      end, [], __ENV__)
    end
  end

  test "raises on invalid opts passed to join/5" do
    assert_raise ArgumentError, ~r/invalid opts passed/, fn ->
      escape(quote do
        join("posts", :left, [p], c in "comments", {:foo, :bar})
      end, [], __ENV__)
    end
  end

  test "raises on invalid binding passed to join/5" do
    assert_raise ArgumentError, ~r/invalid binding passed/, fn ->
      escape(quote do
        join("posts", :inner, [o, p] in subquery(some_subquery), on: o.id == p.org_id)
      end, [], __ENV__)
    end
  end

  test "raises on non-string prefix" do
    assert_raise Ecto.Query.CompileError, ~r/`prefix` must be a compile time string/, fn ->
      escape(quote do
        join("posts", :left, [p], c in "comments", on: true, prefix: :atom)
      end, [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, ~r/`prefix` must be a compile time string/, fn ->
      escape(quote do
        join("posts", :left, [p], c in "comments", on: true, prefix: string)
      end, [], __ENV__)
    end
  end
end
