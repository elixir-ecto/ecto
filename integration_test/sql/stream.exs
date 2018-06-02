defmodule Ecto.Integration.StreamTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post
  alias Ecto.Integration.Comment
  import Ecto.Query

  test "stream empty" do
    assert {:ok, []} = TestRepo.transaction(fn() ->
      TestRepo.stream(Post)
      |> Enum.to_list()
    end)

    assert {:ok, []} = TestRepo.transaction(fn() ->
      TestRepo.stream(from p in Post)
      |> Enum.to_list()
    end)
  end

  test "stream without schema" do
    %Post{} = TestRepo.insert!(%Post{title: "title1"})
    %Post{} = TestRepo.insert!(%Post{title: "title2"})

    assert {:ok, ["title1", "title2"]} = TestRepo.transaction(fn() ->
      TestRepo.stream(from(p in "posts", order_by: p.title, select: p.title))
      |> Enum.to_list()
    end)
  end

  test "stream with assoc" do
    p1 = TestRepo.insert!(%Post{title: "1"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})

    stream = TestRepo.stream(Ecto.assoc(p1, :comments))
    assert {:ok, [c1, c2]} = TestRepo.transaction(fn() ->
      Enum.to_list(stream)
    end)
    assert c1.id == cid1
    assert c2.id == cid2
  end
end
