Code.require_file "../../test_helper.exs", __DIR__

defmodule Ecto.Adapters.PostgresTest do
  use Ecto.PgTest.Case

  import Ecto.Query

  test "fetch empty" do
    assert [] == TestRepo.all(from p in Post)
  end

  test "create and fetch single" do
    assert Post[id: id] = TestRepo.create(Post[title: "The shiny new Ecto", text: "coming soon..."])

    assert is_integer(id)

    assert [Post[id: ^id, title: "The shiny new Ecto", text: "coming soon..."]] =
           TestRepo.all(from p in Post)
  end

  test "create and delete single, fetch nothing" do
    post = Post[title: "The shiny new Ecto", text: "coming soon..."]

    assert Post[] = created = TestRepo.create(post)
    assert :ok == TestRepo.delete(created)

    assert [] = TestRepo.all(from p in Post)
  end

  test "create and delete single, fetch empty" do
    post = Post[title: "The shiny new Ecto", text: "coming soon..."]

    assert Post[] = TestRepo.create(post)
    assert Post[] = created = TestRepo.create(post)
    assert :ok == TestRepo.delete(created)

    assert [Post[]] = TestRepo.all(from p in Post)
  end

  test "create and update single, fetch updated" do
    post = Post[title: "The shiny new Ecto", text: "coming soon..."]

    assert post = TestRepo.create(post)
    post = post.text("coming very soon...")
    assert :ok == TestRepo.update(post)

    assert [Post[text: "coming very soon..."]] = TestRepo.all(from p in Post)
  end

  test "create and fetch multiple" do
    assert Post[] = TestRepo.create(Post[title: "1", text: "hai"])
    assert Post[] = TestRepo.create(Post[title: "2", text: "hai"])
    assert Post[] = TestRepo.create(Post[title: "3", text: "hai"])

    assert [Post[title: "1"], Post[title: "2"], Post[title: "3"]] =
           TestRepo.all(from p in Post)

    assert [Post[title: "2"]] =
           TestRepo.all(from p in Post, where: p.title == "2")
  end
end
