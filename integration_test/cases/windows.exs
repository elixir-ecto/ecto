defmodule Ecto.Integration.WindowsTest do
  use Ecto.Integration.Case, async: Application.get_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Comment
  alias Ecto.Integration.User

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
end
