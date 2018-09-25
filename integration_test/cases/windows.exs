defmodule Ecto.Integration.WindowsTest do
  use Ecto.Integration.Case, async: Application.get_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Comment
  alias Ecto.Integration.User

  test "count over partition" do
    u1 = TestRepo.insert!(%User{name: "Tester"})
    u2 = TestRepo.insert!(%User{name: "Developer"})
    c1 = TestRepo.insert!(%Comment{text: "1", author_id: u1.id})
    c2 = TestRepo.insert!(%Comment{text: "2", author_id: u1.id})
    c3 = TestRepo.insert!(%Comment{text: "3", author_id: u1.id})
    c4 = TestRepo.insert!(%Comment{text: "4", author_id: u2.id})

    query = from(c in Comment, select: [c, count(c.id) |> over(partition_by(c.author_id))])

    assert [[^c1, 3], [^c2, 3], [^c3, 3], [^c4, 1]] = TestRepo.all(query)
  end

  test "last 2 of each author" do
    u1 = TestRepo.insert!(%User{name: "Tester"})
    u2 = TestRepo.insert!(%User{name: "Developer"})
    TestRepo.insert!(%Comment{text: "1", author_id: u1.id})
    TestRepo.insert!(%Comment{text: "2", author_id: u1.id})
    TestRepo.insert!(%Comment{text: "3", author_id: u1.id})
    TestRepo.insert!(%Comment{text: "4", author_id: u2.id})

    subquery = from(c in Comment,
      windows: [rw: partition_by(c.author_id, order_by: :id)],
      select: %{
        comment: c.text,
        row: row_number() |> over(:rw),
        total: count(c.id) |> over(partition_by(c.author_id))
      },
      where: c.author_id in [^u1.id, ^u2.id]
    )

    query = from(r in subquery(subquery),
      select: r.comment,
      where: (r.total - r.row) < 2
    )

    assert ["2", "3", "4"] = TestRepo.all(query)
  end
end
