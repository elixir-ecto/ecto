defmodule Ecto.Integration.CopyTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "stream copy to and from table" do
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

  test "stage copy to and from table" do
    one = TestRepo.insert!(%Post{title: "one"})
    two = TestRepo.insert!(%Post{title: "two"})

    read = "COPY posts TO STDOUT"
    {:ok, producer} = Ecto.Adapters.SQL.start_stage(TestRepo, read, [], [])

    data =
      [{producer, cancel: :transient}]
      |> GenStage.stream()
      |> Enum.to_list()

    assert TestRepo.delete_all(Post) == {2, nil}

    write = "COPY posts FROM STDIN"
    {:ok, consumer} = Ecto.Adapters.SQL.start_stage(TestRepo, write, [], [stage_module: Postgrex.CopyConsumer])

    {:ok, _} =
      data
      |> Flow.from_enumerable()
      |> Flow.into_stages([consumer])

    assert TestRepo.all(Post) == [one, two]
  end
end
