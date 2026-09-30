defmodule Ecto.Integration.JSONTest do
  use Ecto.Integration.Case, async: Application.compile_env(:ecto, :async_integration_tests, true)

  import Ecto.Query

  alias Ecto.Integration.{Comment, Permalink, Post, TestRepo, User}

  @moduletag :json_functions

  test "object construction decodes nested objects, JSON fields, keys and typed values" do
    post = TestRepo.insert!(%Post{meta: %{"tags" => ["one", "two"]}})
    name = "O'Brien \u00e9"

    query =
      from p in Post,
        select:
          json_build_object(%{
            "quoted'key" => type(^name, :string),
            id: p.id,
            meta: p.meta,
            nested: json_build_object(%{present: true, missing: nil}),
            empty: json_build_object(%{})
          })

    assert TestRepo.one!(query) == %{
             "quoted'key" => name,
             "id" => post.id,
             "meta" => %{"tags" => ["one", "two"]},
             "nested" => %{"present" => true, "missing" => nil},
             "empty" => %{}
           }

    query = from p in Post, select: type(json_build_object(%{id: p.id}), :map)
    assert TestRepo.one!(query) == %{"id" => post.id}

    incompatible_type = :integer

    assert_raise Postgrex.Error, fn ->
      TestRepo.one!(
        from p in Post, select: type(json_build_object(%{id: p.id}), ^incompatible_type)
      )
    end
  end

  test "scalar and object aggregates distinguish empty input from null values" do
    assert TestRepo.one!(from p in Post, select: json_agg(p.visits)) == []
    assert TestRepo.all(from p in Post, select: json_build_object(%{id: p.id})) == []
    assert TestRepo.all(from p in Post, group_by: p.public, select: json_agg(p.id)) == []

    TestRepo.insert!(%Post{visits: nil})
    TestRepo.insert!(%Post{visits: 2})
    TestRepo.insert!(%Post{visits: 1})

    assert TestRepo.one!(from p in Post, select: json_agg(p.visits, order_by: [asc: p.id])) ==
             [nil, 2, 1]

    assert TestRepo.one!(
             from p in Post, select: json_agg(p.visits, order_by: [desc_nulls_last: p.visits])
           ) ==
             [2, 1, nil]

    assert TestRepo.one!(from p in Post, select: filter(json_agg(p.visits), p.visits > 10)) == []

    assert TestRepo.one!(
             from p in Post,
               select: filter(json_agg(p.visits, order_by: [asc: p.visits]), not is_nil(p.visits))
           ) == [1, 2]

    assert TestRepo.one!(
             from p in Post,
               select: json_agg(json_build_object(%{visits: p.visits}), order_by: [asc: p.id])
           ) == [%{"visits" => nil}, %{"visits" => 2}, %{"visits" => 1}]
  end

  test "arrays retain JSON values without loading each element as its field type" do
    TestRepo.insert!(%Post{wrapped_visits: {:int, 10}, meta: %{"nested" => [1, nil, "text"]}})
    assert TestRepo.one!(from p in Post, select: json_agg(p.wrapped_visits)) == [10]

    assert TestRepo.one!(from p in Post, select: json_agg(p.meta)) == [
             %{"nested" => [1, nil, "text"]}
           ]

    assert TestRepo.one!(from p in Post, select: json_agg(type(^"text", :string))) == ["text"]

    assert TestRepo.one!(
             from p in Post, select: json_agg(fragment("json_build_array(1, true, null)"))
           ) ==
             [[1, true, nil]]
  end

  test "JSON expressions preserve custom field sources and subquery result types" do
    permalink = TestRepo.insert!(%Permalink{url: "https://example.test"})
    inner = from p in Permalink, select: %{object: json_build_object(%{url: p.url})}

    assert TestRepo.one!(from s in subquery(inner), select: s.object) ==
             %{"url" => permalink.url}

    query =
      from(p in "json_values", select: type(p.object, :map))
      |> with_cte("json_values", as: ^inner)

    assert TestRepo.one!(query) == %{"url" => permalink.url}

    aggregate = from p in Permalink, select: %{array: json_agg(p.url)}
    assert TestRepo.one!(from s in subquery(aggregate), select: s.array) == [permalink.url]

    query =
      from(p in Permalink, select: %{id: p.id})
      |> select_merge([p], %{object: json_build_object(%{url: p.url})})

    assert TestRepo.one!(query) == %{id: permalink.id, object: %{"url" => permalink.url}}
  end

  test "window normalization follows FILTER and OVER, including empty frames" do
    TestRepo.insert!(%Post{visits: 2})
    TestRepo.insert!(%Post{visits: 1})

    query =
      from p in Post,
        order_by: p.id,
        select: over(json_agg(p.visits), :all),
        windows: [all: [partition_by: p.public]]

    assert Enum.map(TestRepo.all(query), &Enum.sort/1) == [[1, 2], [1, 2]]

    query =
      from p in Post,
        order_by: p.id,
        select: over(filter(json_agg(p.visits), p.visits > 10), partition_by: p.public)

    assert TestRepo.all(query) == [[], []]

    query =
      from p in Post,
        order_by: p.id,
        select:
          over(json_agg(p.visits),
            order_by: p.id,
            frame: fragment("ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING")
          )

    assert TestRepo.all(query) == [[], [2]]
  end

  test "correlated JSON subqueries preserve the parent limit and match equivalent fragments" do
    posts = for _ <- 1..101, do: TestRepo.insert!(%Post{})
    [first | _] = posts
    last = List.last(posts)
    user1 = TestRepo.insert!(%User{name: "Same name"})
    user2 = TestRepo.insert!(%User{name: "Same name"})
    TestRepo.insert!(%Comment{post_id: first.id, author_id: user1.id, lock_version: 1})
    TestRepo.insert!(%Comment{post_id: first.id, author_id: user2.id, lock_version: 2})
    TestRepo.insert!(%Comment{post_id: last.id, author_id: user1.id, lock_version: 2})

    children =
      from c in Comment,
        join: u in User,
        on: u.id == c.author_id,
        where: c.post_id == parent_as(:post).id,
        select:
          json_agg(
            json_build_object(%{primary: c.lock_version > 1, name: u.name}),
            order_by: [desc: c.lock_version]
          )

    query =
      from p in Post,
        as: :post,
        order_by: p.id,
        limit: 100,
        select: %{id: p.id, children: subquery(children)}

    results = TestRepo.all(query)
    assert length(results) == 100

    assert hd(results) == %{
             id: first.id,
             children: [
               %{"primary" => true, "name" => "Same name"},
               %{"primary" => false, "name" => "Same name"}
             ]
           }

    assert Enum.all?(tl(results), &(&1.children == []))
    refute Enum.any?(results, &(&1.id == last.id))

    fragment_children =
      children
      |> exclude(:select)
      |> select(
        [c, u],
        fragment(
          "coalesce(json_agg(json_build_object('primary', ? > 1, 'name', ?) ORDER BY ? DESC), '[]'::json)",
          c.lock_version,
          u.name,
          c.lock_version
        )
      )

    baseline =
      query
      |> exclude(:select)
      |> select([p], %{id: p.id, children: subquery(fragment_children)})

    assert TestRepo.all(baseline) == results
    assert explain(query) == explain(baseline)
  end

  test "left join placeholders must be filtered out explicitly" do
    TestRepo.insert!(%Post{})

    query =
      from p in Post,
        left_join: c in Comment,
        on: c.post_id == p.id,
        select: %{unfiltered: json_agg(c.id), filtered: filter(json_agg(c.id), not is_nil(c.id))}

    assert TestRepo.one!(query) == %{unfiltered: [nil], filtered: []}
  end

  defp explain(query) do
    {sql, params} = Ecto.Adapters.SQL.to_sql(:all, TestRepo, query)
    Ecto.Adapters.SQL.query!(TestRepo, "EXPLAIN (FORMAT JSON) " <> sql, params).rows
  end
end
