Code.require_file "../support/types.exs", __DIR__

defmodule Ecto.Integration.TypeTest do
  use Ecto.Integration.Case

  require Ecto.Integration.TestRepo, as: TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.Tag
  alias Ecto.Integration.Custom

  test "primitive types" do
    integer  = 1
    float    = 0.1
    text     = <<0,1>>
    uuid     = "00010203-0405-0607-0809-0a0b0c0d0e0f"
    datetime = %Ecto.DateTime{year: 2014, month: 1, day: 16,
                              hour: 20, min: 26, sec: 51, usec: 0}

    TestRepo.insert!(%Post{text: text, public: true, visits: integer, uuid: uuid, counter: integer,
                          inserted_at: datetime, intensity: float})

    # nil
    assert [nil] = TestRepo.all(from Post, select: nil)

    # ID
    assert [1] = TestRepo.all(from p in Post, where: p.counter == ^integer, select: p.counter)

    # Integers
    assert [1] = TestRepo.all(from p in Post, where: p.visits == ^integer, select: p.visits)
    assert [1] = TestRepo.all(from p in Post, where: p.visits == 1, select: p.visits)

    # Floats
    assert [0.1] = TestRepo.all(from p in Post, where: p.intensity == ^float, select: p.intensity)
    assert [0.1] = TestRepo.all(from p in Post, where: p.intensity == 0.1, select: p.intensity)

    # Booleans
    assert [true] = TestRepo.all(from p in Post, where: p.public == ^true, select: p.public)
    assert [true] = TestRepo.all(from p in Post, where: p.public == true, select: p.public)

    # Binaries
    assert [^text] = TestRepo.all(from p in Post, where: p.text == <<0, 1>>, select: p.text)
    assert [^text] = TestRepo.all(from p in Post, where: p.text == ^text, select: p.text)

    # UUID
    assert [^uuid] = TestRepo.all(from p in Post, where: p.uuid == ^uuid, select: p.uuid)

    # Datetime
    assert [^datetime] = TestRepo.all(from p in Post, where: p.inserted_at == ^datetime, select: p.inserted_at)
  end

  @tag :decimal_type
  test "decimal type" do
    decimal = Decimal.new("1.0")

    TestRepo.insert!(%Post{cost: decimal})

    assert [^decimal] = TestRepo.all(from p in Post, where: p.cost == ^decimal, select: p.cost)
    assert [^decimal] = TestRepo.all(from p in Post, where: p.cost == ^1.0, select: p.cost)
    assert [^decimal] = TestRepo.all(from p in Post, where: p.cost == ^1, select: p.cost)
    assert [^decimal] = TestRepo.all(from p in Post, where: p.cost == 1.0, select: p.cost)
    assert [^decimal] = TestRepo.all(from p in Post, where: p.cost == 1, select: p.cost)
  end

  test "tagged types" do
    TestRepo.insert!(%Post{})

    # Integer
    assert [1]   = TestRepo.all(from Post, select: type(^"1", :integer))
    assert [1.0] = TestRepo.all(from Post, select: type(^1.0, :float))

    # Datetime
    datetime = {{2014, 04, 17}, {14, 00, 00, 00}}
    assert [^datetime] = TestRepo.all(from Post, select: type(^datetime, :datetime))

    # Custom wrappers
    assert [1] = TestRepo.all(from Post, select: type(^"1", Elixir.Custom.Permalink))

    # Custom types
    datetime = %Ecto.DateTime{year: 2014, month: 1, day: 16, hour: 20, min: 26, sec: 51, usec: 0}
    assert [^datetime] = TestRepo.all(from Post, select: type(^datetime, Ecto.DateTime))
  end

  test "binary id type" do
    assert %Custom{} = custom = TestRepo.insert!(%Custom{})
    bid = custom.bid
    assert [^bid] = TestRepo.all(from c in Custom, select: c.bid)
    assert [^bid] = TestRepo.all(from c in Custom, select: type(^bid, :binary_id))
  end

  test "composite types in select" do
    assert %Post{} = TestRepo.insert!(%Post{title: "1", text: "hai"})

    assert [{"1", "hai"}] ==
           TestRepo.all(from p in Post, select: {p.title, p.text})

    assert [["1", "hai"]] ==
           TestRepo.all(from p in Post, select: [p.title, p.text])

    assert [%{:title => "1", 3 => "hai", "text" => "hai"}] ==
           TestRepo.all(from p in Post, select: %{
             :title => p.title,
             "text" => p.text,
             3 => p.text
           })
  end

  @tag :array_type
  test "array type" do
    TestRepo.insert!(%Tag{ints: [1, 2, 3], uuids: ["51FCFBDD-AD60-4CCB-8BF9-47AABD66D075"]})

    assert [] = TestRepo.all(from p in Tag, where: p.ints == ^[], select: p.ints)
    assert [[1, 2, 3]] = TestRepo.all(from p in Tag, where: p.ints == ^[1, 2, 3], select: p.ints)
    assert [[1, 2, 3]] = TestRepo.all(from p in Tag, where: p.ints == [1, 2, 3], select: p.ints)

    assert [] = TestRepo.all(from p in Tag, where: p.uuids == ^[], select: p.uuids)
    assert [["51fcfbdd-ad60-4ccb-8bf9-47aabd66d075"]] =
           TestRepo.all(from p in Tag, where: p.uuids == ^["51FCFBDD-AD60-4CCB-8BF9-47AABD66D075"],
                                       select: p.uuids)
  end
end
