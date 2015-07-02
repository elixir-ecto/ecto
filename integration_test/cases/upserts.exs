defmodule Ecto.Integration.Upserts do
  use Ecto.Integration.Case

  require Ecto.Integration.TestRepo, as: TestRepo

  alias Ecto.Integration.Post

  test "update if record exists on insert" do
    p1 = TestRepo.insert!(%Post{title: "1", visits: 1})
    TestRepo.insert!(%Post{title: "2", id: p1.id, visits: 3}, if_exists: :update)

    p1 = TestRepo.get(Post, p1.id)
    assert p1.title == "2"
    assert p1.visits == 3
  end

  test "ignore if record exists on insert" do
    p1 = TestRepo.insert!(%Post{title: "1", visits: 1})
    TestRepo.insert!(%Post{title: "2", id: p1.id, visits: 3}, if_exists: :ignore)

    p1 = TestRepo.get(Post, p1.id)
    assert p1.title == "1"
    assert p1.visits == 1
  end

  test "error if record exists on insert" do
    p1 = TestRepo.insert!(%Post{title: "1", visits: 1})

    assert_raise Postgrex.Error, fn ->
      TestRepo.insert!(%Post{title: "2", id: p1.id, visits: 3}, if_exists: :error)
    end
  end

  test "insert if record exists on update" do
  end

  test "ignore if record exists on update" do
  end

  test "error if record exists on update" do
  end
end
