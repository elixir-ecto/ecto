Code.require_file "../support/types.exs", __DIR__

defmodule Ecto.Integration.TypeTest do
  use Ecto.Integration.Case

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.Tag
  alias Ecto.Integration.Custom
  alias Ecto.Integration.Order
  alias Ecto.Integration.Item

  test "primitive types" do
    integer  = 1
    float    = 0.1
    text     = <<0,1>>
    uuid     = "00010203-0405-0607-0809-0a0b0c0d0e0f"
    datetime = %Ecto.DateTime{year: 2014, month: 1, day: 16,
                              hour: 20, min: 26, sec: 51, usec: 0}

    TestRepo.insert!(%Post{text: text, public: true, visits: integer, uuid: uuid,
                           counter: integer, inserted_at: datetime, intensity: float})

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
    assert [1500.0] = TestRepo.all(from p in Post, select: 1500.0)

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

  test "tagged types" do
    TestRepo.insert!(%Post{})

    # Numbers
    assert [1]   = TestRepo.all(from Post, select: type(^"1", :integer))
    assert [1.0] = TestRepo.all(from Post, select: type(^1.0, :float))
    assert [1]   = TestRepo.all(from p in Post, select: type(^"1", p.visits))
    assert [1.0] = TestRepo.all(from p in Post, select: type(^"1", p.intensity))

    # Datetime
    datetime = {{2014, 04, 17}, {14, 00, 00, 00}}
    ecto_datetime = %Ecto.DateTime{year: 2014, month: 4, day: 17, hour: 14, min: 0, sec: 0, usec: 0}
    assert [^ecto_datetime] = TestRepo.all(from Post, select: type(^datetime, Ecto.DateTime))

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

    assert [%{:title => "1", "1" => "hai", "text" => "hai"}] ==
           TestRepo.all(from p in Post, select: %{
             :title  => p.title,
             p.title => p.text,
             "text"  => p.text
           })
  end

  @tag :array_type
  test "array type" do
    ints = [1, 2, 3]
    tag = TestRepo.insert!(%Tag{ints: ints})

    assert TestRepo.all(from t in Tag, where: t.ints == ^[], select: t.ints) == []
    assert TestRepo.all(from t in Tag, where: t.ints == ^[1, 2, 3], select: t.ints) == [ints]

    # Querying
    assert TestRepo.all(from t in Tag, where: t.ints == [1, 2, 3], select: t.ints) == [ints]
    assert TestRepo.all(from t in Tag, where: 0 in t.ints, select: t.ints) == []
    assert TestRepo.all(from t in Tag, where: 1 in t.ints, select: t.ints) == [ints]

    # Update
    tag = TestRepo.update!(Ecto.Changeset.change tag, ints: [3, 2, 1])
    assert TestRepo.get!(Tag, tag.id).ints == [3, 2, 1]

    # Update all
    {1, _} = TestRepo.update_all(Tag, push: [ints: 0])
    assert TestRepo.get!(Tag, tag.id).ints == [3, 2, 1, 0]

    {1, _} = TestRepo.update_all(Tag, pull: [ints: 2])
    assert TestRepo.get!(Tag, tag.id).ints == [3, 1, 0]
  end

  @tag :array_type
  test "array type with custom types" do
    uuids = ["51fcfbdd-ad60-4ccb-8bf9-47aabd66d075"]
    TestRepo.insert!(%Tag{uuids: ["51fcfbdd-ad60-4ccb-8bf9-47aabd66d075"]})

    assert TestRepo.all(from t in Tag, where: t.uuids == ^[], select: t.uuids) == []
    assert TestRepo.all(from t in Tag, where: t.uuids == ^["51fcfbdd-ad60-4ccb-8bf9-47aabd66d075"],
                                       select: t.uuids) == [uuids]
  end

  @tag :array_type
  test "array type with nil in array" do
    tag = TestRepo.insert!(%Tag{ints: [1, nil, 3]})
    assert tag.ints == [1, nil, 3]
  end

  @tag :map_type
  test "map type" do
    post1 = TestRepo.insert!(%Post{meta: %{"foo" => "bar", "baz" => "bat"}})
    post2 = TestRepo.insert!(%Post{meta: %{foo: "bar", baz: "bat"}})

    assert TestRepo.all(from p in Post, where: p.id == ^post1.id, select: p.meta) ==
           [%{"foo" => "bar", "baz" => "bat"}]
    assert TestRepo.all(from p in Post, where: p.id == ^post2.id, select: p.meta) ==
           [%{"foo" => "bar", "baz" => "bat"}]
  end

  @tag :map_type
  test "map type on update" do
    post = TestRepo.insert!(%Post{meta: %{"world" => "hello"}})
    assert TestRepo.get!(Post, post.id).meta == %{"world" => "hello"}

    post = TestRepo.update!(Ecto.Changeset.change post, meta: %{hello: "world"})
    assert TestRepo.get!(Post, post.id).meta == %{"hello" => "world"}

    query = from(p in Post, where: p.id == ^post.id)
    TestRepo.update_all(query, set: [meta: %{world: "hello"}])
    assert TestRepo.get!(Post, post.id).meta == %{"world" => "hello"}
  end

  @tag :map_type
  test "embeds one" do
    item = %Item{price: 123, valid_at: Ecto.Date.utc}
    order =
      %Order{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:item, item)
    order = TestRepo.insert!(order)
    dbitem = TestRepo.get!(Order, order.id).item
    assert item.price == dbitem.price
    assert item.valid_at == dbitem.valid_at
    assert dbitem.id

    [dbitem] = TestRepo.all(from o in Order, select: o.item)
    assert item.price == dbitem.price
    assert item.valid_at == dbitem.valid_at
    assert dbitem.id

    {1, _} = TestRepo.update_all(Order, set: [item: %{dbitem | price: 456}])
    assert TestRepo.get!(Order, order.id).item.price == 456
  end

  @tag :map_type
  @tag :array_type
  test "embeds many" do
    item = %Item{price: 123, valid_at: Ecto.Date.utc}
    tag =
      %Tag{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:items, [item])
    tag = TestRepo.insert!(tag)

    [dbitem] = TestRepo.get!(Tag, tag.id).items
    assert item.price == dbitem.price
    assert item.valid_at == dbitem.valid_at
    assert dbitem.id

    [[dbitem]] = TestRepo.all(from t in Tag, select: t.items)
    assert item.price == dbitem.price
    assert item.valid_at == dbitem.valid_at
    assert dbitem.id

    {1, _} = TestRepo.update_all(Tag, set: [items: [%{dbitem | price: 456}]])
    assert (TestRepo.get!(Tag, tag.id).items |> hd).price == 456
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
end
