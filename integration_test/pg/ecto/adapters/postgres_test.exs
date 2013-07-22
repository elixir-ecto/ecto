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

  test "create and delete single, fetch empty" do
    post = Post[title: "The shiny new Ecto", text: "coming soon..."]

    assert Post[] = TestRepo.create(post)
    assert Post[] = created = TestRepo.create(post)
    assert :ok == TestRepo.delete(created)

    assert [Post[]] = TestRepo.all(from p in Post)
  end
end
