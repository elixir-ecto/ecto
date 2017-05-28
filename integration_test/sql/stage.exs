defmodule Ecto.Integration.StageTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.TestStage
  alias Ecto.Integration.Post
  alias Ecto.Integration.Comment
  import Ecto.Query

  test "stream empty" do
    {:ok, stage} = TestStage.start_link(Post)
    assert to_list(stage) === []

    {:ok, stage} = TestStage.start_link(from p in Post)
    assert to_list(stage) == []
  end

  test "stream without schema" do
    %Post{} = TestRepo.insert!(%Post{title: "title1"})
    %Post{} = TestRepo.insert!(%Post{title: "title2"})

    query = from(p in "posts", order_by: p.title, select: p.title)
    {:ok, stage} = TestStage.start_link(query)

    assert to_list(stage) == ["title1", "title2"]
  end

  test "stream with assoc" do
    p1 = TestRepo.insert!(%Post{title: "1"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})

    {:ok, stage} = TestStage.start_link(Ecto.assoc(p1, :comments))
    assert [c1, c2] = to_list(stage)

    assert c1.id == cid1
    assert c2.id == cid2
  end

  test "stream with preload" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    TestRepo.insert!(%Post{title: "3"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "3", post_id: p2.id})
    %Comment{id: cid4} = TestRepo.insert!(%Comment{text: "4", post_id: p2.id})

    query = from(p in Post, preload: [:comments], select: p)
    {:ok, stage} = TestStage.start_link(query, [max_rows: 2])

    assert [p1, p2, p3] = stage |> to_list() |> sort_by_id()

    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = p1.comments |> sort_by_id
    assert [%Comment{id: ^cid3}, %Comment{id: ^cid4}] = p2.comments |> sort_by_id
    assert [] = p3.comments
  end

  defp to_list(stage) do
    stage
    |> Flow.from_stage()
    |> Enum.to_list()
  end

  defp sort_by_id(values) do
    Enum.sort_by(values, &(&1.id))
  end
end
