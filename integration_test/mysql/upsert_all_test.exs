Code.require_file "../support/types.exs", __DIR__

defmodule Ecto.Integration.UpsertAllTest do
  use Ecto.Integration.Case

  alias Ecto.Integration.TestRepo
  import Ecto.Query
  alias Ecto.Integration.Post


  test "on conflict raise" do
    post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
    {1, nil} = TestRepo.insert_all(Post, [post], on_conflict: :raise)
    assert catch_error(TestRepo.insert_all(Post, [post], on_conflict: :raise))
  end

  test "on conflict ignore" do
    post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
    assert TestRepo.insert_all(Post, [post], on_conflict: :nothing) ==
           {1, nil}
    assert TestRepo.insert_all(Post, [post], on_conflict: :nothing) ==
           {1, nil}
  end

  test "on conflict keyword list" do
    on_conflict = [set: [title: "second"]]
    post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
    {1, nil} = TestRepo.insert_all(Post, [post], on_conflict: on_conflict)

    assert TestRepo.insert_all(Post, [post], on_conflict: on_conflict) ==
           {2, nil}
    assert TestRepo.all(from p in Post, select: p.title) == ["second"]
  end

  test "on conflict query and conflict target" do
    on_conflict = from Post, update: [set: [title: "second"]]
    post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
    assert TestRepo.insert_all(Post, [post], on_conflict: on_conflict) ==
           {1, nil}

    assert TestRepo.insert_all(Post, [post], on_conflict: on_conflict) ==
           {2, nil}
    assert TestRepo.all(from p in Post, select: p.title) == ["second"]
  end
end
