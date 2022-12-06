Code.require_file "../../../support/eval_helpers.exs", __DIR__

defmodule Ecto.Query.Builder.PreloadTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Preload
  doctest Ecto.Query.Builder.Preload

  import Ecto.Query
  import Support.EvalHelpers

  test "raises on invalid preloads" do
    assert_raise Ecto.Query.CompileError, ~r"`1` is not a valid preload expression", fn ->
      quote_and_eval(%Ecto.Query{} |> preload(1))
    end

    message = "expected key in preload to be an atom, got: `1`"
    assert_raise ArgumentError, message, fn ->
      temp = 1
      preload(%Ecto.Query{}, [{^temp, :foo}])
    end
  end

  test "accumulates on multiple calls" do
    query = %Ecto.Query{} |> preload(:foo) |> preload(:bar)
    assert query.preloads == [:foo, :bar]
  end

  describe "at runtime" do
    test "supports interpolation" do
      comments = :comments
      assert preload("posts", ^comments).preloads == [:comments]
      assert preload("posts", ^[comments]).preloads == [:comments]
      assert preload("posts", [users: ^comments]).preloads == [users: :comments]
      assert preload("posts", ^[users: comments]).preloads == [users: :comments]
      assert preload("posts", [users: ^[comments]]).preloads == [users: [:comments]]
      assert preload("posts", ^[users: [comments]]).preloads == [users: [:comments]]
      assert preload("posts", [{^:users, ^comments}]).preloads == [users: :comments]

      query = from u in "users", limit: 10
      assert preload("posts", [users: ^query]).preloads == [users: query]
      assert preload("posts", [{^:users, ^query}]).preloads == [users: query]
      assert preload("posts", ^[users: query]).preloads == [users: query]
      assert preload("posts", [users: ^{query, :comments}]).preloads == [users: {query, :comments}]
      assert preload("posts", ^[users: {query, :comments}]).preloads == [users: {query, [:comments]}]

      fun = fn _ -> [] end
      assert preload("posts", [users: ^fun]).preloads == [users: fun]
      assert preload("posts", [{^:users, ^fun}]).preloads == [users: fun]
      assert preload("posts", ^[users: fun]).preloads == [users: fun]
      assert preload("posts", [users: ^{fun, :comments}]).preloads == [users: {fun, :comments}]
      assert preload("posts", ^[users: {fun, :comments}]).preloads == [users: {fun, [:comments]}]
    end

    test "supports interpolation with associations" do
      comments = :comments

      query = from p in "posts", join: c in assoc(p, :comments), as: ^comments
      assert %{preloads: [], assocs: [{:comments, {1, []}}]} =
               preload(query, [{^comments, c}], [{^comments, c}])
      assert %{preloads: [:foo], assocs: [{:comments, {1, []}}]} =
               preload(query, [{^comments, c}], [:foo, {^comments, c}])

      query =
        from p in "posts",
          join: f in assoc(p, :foo), as: :foo,
          join: c in assoc(f, :comments), as: ^comments
      assert %{preloads: [], assocs: [{:foo, {1, [{:comments, {2, []}}]}}]} =
               preload(query, [{:foo, f}, {^comments, c}], [foo: {f, [{^comments, c}]}])
    end

    test "supports dynamics with associations" do
      comments = :comments

      query = from p in "posts", join: c in assoc(p, :comments), as: ^comments
      preloads = [comments: dynamic([{^comments, c}], c)]
      assert %{preloads: [], assocs: [comments: {1, []}]} = preload(query, ^preloads)

      query =
        from p in "posts",
        join: c in assoc(p, :comments), as: ^comments,
        join: l in assoc(p, :likes), as: :likes
      preloads = [
        likes: dynamic([likes: l], l),
        comments: dynamic([{^comments, c}], c)
      ]
      assert %{preloads: [], assocs: [likes: {2, []}, comments: {1, []}]} =
               preload(query, ^preloads)

      query =
        from p in "posts",
        join: c in assoc(p, :comments),
        join: l in assoc(c, :likes)
      preloads = [comments: {dynamic([_, c], c), likes: dynamic([_, _, l], l)}]
      assert %{preloads: [], assocs: [comments: {1, [likes: {2, []}]}]} =
               preload(query, ^preloads)
    end
  end
end
