defmodule Ecto.Integration.WindowsTest do
  use Ecto.Integration.Case, async: Application.get_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.{Comment, User, Post}

  test "over" do
    u1 = TestRepo.insert!(%User{name: "Tester"})
    u2 = TestRepo.insert!(%User{name: "Developer"})
    c1 = TestRepo.insert!(%Comment{text: "1", author_id: u1.id})
    c2 = TestRepo.insert!(%Comment{text: "2", author_id: u1.id})
    c3 = TestRepo.insert!(%Comment{text: "3", author_id: u1.id})
    c4 = TestRepo.insert!(%Comment{text: "4", author_id: u2.id})

    # Over nothing
    query = from(c in Comment, select: [c, count(c.id) |> over()])
    assert [[^c1, 4], [^c2, 4], [^c3, 4], [^c4, 4]] = TestRepo.all(query)

    # Over partition
    query = from(c in Comment, select: [c, count(c.id) |> over(partition_by: c.author_id)])
    assert [[^c1, 3], [^c2, 3], [^c3, 3], [^c4, 1]] = TestRepo.all(query)

    # Over window
    query = from(c in Comment, windows: [w: [partition_by: c.author_id]], select: [c, count(c.id) |> over(:w)])
    assert [[^c1, 3], [^c2, 3], [^c3, 3], [^c4, 1]] = TestRepo.all(query)
  end

  test "frame" do
    posts = Enum.map(0..6, &%{counter: &1, visits: round(:math.pow(2, &1))})
    TestRepo.insert_all(Post, posts)

    n = 1
    query = from(p in Post,
      windows: [w: [order_by: p.counter, frame: fragment("ROWS BETWEEN ? PRECEDING AND ? FOLLOWING", ^n, ^n)]],
      select: [p.counter, sum(p.visits) |> over(:w)]
    )
    assert [[0, 3], [1, 7], [2, 14], [3, 28], [4, 56], [5, 112], [6, 96]] = TestRepo.all(query)

    query = from(p in Post,
      windows: [w: [order_by: p.counter, frame: fragment("ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING")]],
      select: [p.counter, sum(p.visits) |> over(:w)]
    )
    assert [[0, 126], [1, 124], [2, 120], [3, 112], [4, 96], [5, 64], [6, nil]] = TestRepo.all(query)

    query = from(p in Post,
      windows: [w: [order_by: p.counter, frame: fragment("ROWS CURRENT ROW")]],
      select: [p.counter, sum(p.visits) |> over(:w)]
    )
    assert [[0, 1], [1, 2], [2, 4], [3, 8], [4, 16], [5, 32], [6, 64]] = TestRepo.all(query)
  end
end
