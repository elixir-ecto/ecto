defmodule Ecto.Integration.CopyTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "copy to and from table" do
    read = Ecto.Adapters.SQL.stream(TestRepo, "COPY posts TO STDOUT")
    write = Ecto.Adapters.SQL.stream(TestRepo, "COPY posts FROM STDIN")

    TestRepo.transaction fn ->
      one = TestRepo.insert!(%Post{title: "one"})
      two = TestRepo.insert!(%Post{title: "two"})

      data = Enum.map(read, &(&1.rows))
      assert TestRepo.delete_all(Post) == {2, nil}

      assert ^write = Enum.into(data, write)
      assert TestRepo.all(Post) == [one, two]
    end
  end
end
