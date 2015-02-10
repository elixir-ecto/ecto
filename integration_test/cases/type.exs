defmodule Ecto.Integration.TypeTest do
  use Ecto.Integration.Case

  require Ecto.Integration.TestRepo, as: TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.Tag

  test "primitive types" do
    text     = <<0,1>>
    uuid     = <<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>
    decimal  = Decimal.new("1.0")
    datetime = %Ecto.DateTime{year: 2014, month: 1, day: 16, hour: 20, min: 26, sec: 51}
    TestRepo.insert(%Post{text: text, uuid: uuid, public: true,
                          inserted_at: datetime, cost: decimal})

    # nil
    assert [nil] = TestRepo.all(from Post, select: nil)

    # Numbers
    assert [{1, 1.0}] = TestRepo.all(from Post, select: {1, 1.0})

    # Decimal
    assert [^decimal] = TestRepo.all(from p in Post, where: p.cost == ^decimal, select: p.cost)
    assert [^decimal] = TestRepo.all(from p in Post, where: p.cost == ^1.0, select: p.cost)
    assert [^decimal] = TestRepo.all(from p in Post, where: p.cost == ^1, select: p.cost)
    assert [^decimal] = TestRepo.all(from p in Post, where: p.cost == 1.0, select: p.cost)
    assert [^decimal] = TestRepo.all(from p in Post, where: p.cost == 1, select: p.cost)

    # Booleans
    assert [true] = TestRepo.all(from p in Post, where: p.public == ^true, select: p.public)
    assert [true] = TestRepo.all(from p in Post, where: p.public == true, select: p.public)

    # Binaries
    assert [^text] = TestRepo.all(from p in Post, where: p.text == ^text, select: p.text)
    assert [^text] = TestRepo.all(from p in Post, where: p.text == <<0, 1>>, select: p.text)

    # UUID
    assert [^uuid] = TestRepo.all(from p in Post, where: p.uuid == ^uuid, select: p.uuid)
    assert [^uuid] = TestRepo.all(from p in Post, where: p.uuid == uuid(<<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>), select: p.uuid)

    # Datetime
    assert [^datetime] = TestRepo.all(from p in Post, where: p.inserted_at == ^datetime, select: p.inserted_at)
  end

  test "tagged types" do
    TestRepo.insert(%Post{})

    # Integer
    assert [1]   = TestRepo.all(from Post, select: type(^"1", :integer))
    assert [1.0] = TestRepo.all(from Post, select: type(^1.0, :float))

    # UUID
    uuid = <<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>
    assert [^uuid] = TestRepo.all(from Post, select: type(^uuid, :uuid))

    # Datetime
    datetime = {{2014, 04, 17}, {14, 00, 00}}
    assert [^datetime] = TestRepo.all(from Post, select: type(^datetime, :datetime))

    # Custom wrappers
    assert [1] = TestRepo.all(from Post, select: type(^"1", Elixir.Custom.Permalink))

    # Custom types
    datetime = %Ecto.DateTime{year: 2014, month: 1, day: 16, hour: 20, min: 26, sec: 51}
    assert [^datetime] = TestRepo.all(from Post, select: type(^datetime, Ecto.DateTime))
  end

  test "composite types in select" do
    assert %Post{} = TestRepo.insert(%Post{title: "1", text: "hai"})

    assert [{"1", "hai"}] ==
           TestRepo.all(from p in Post, select: {p.title, p.text})

    assert [["1", "hai"]] ==
           TestRepo.all(from p in Post, select: [p.title, p.text])
  end

  @tag :array_type
  test "array type" do
    TestRepo.insert(%Tag{tags: [1, 2, 3]})
    assert [[1, 2, 3]] = TestRepo.all(from Tag, select: [1, 2, 3])

    assert [] = TestRepo.all(from p in Tag, where: p.tags == ^[], select: p.tags)
    assert [[1, 2, 3]] = TestRepo.all(from p in Tag, where: p.tags == ^[1, 2, 3], select: p.tags)
    assert [[1, 2, 3]] = TestRepo.all(from p in Tag, where: p.tags == [1, 2, 3], select: p.tags)
  end
end
