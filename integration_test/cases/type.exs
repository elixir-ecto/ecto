defmodule Ecto.Integration.TypeTest do
  use Ecto.Integration.Case, async: Application.get_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.{Custom, Item, ItemColor, Order, Post, User, Tag, Usec}
  alias Ecto.Integration.TestRepo
  import Ecto.Query

  test "primitive types" do
    integer  = 1
    float    = 0.1
    blob     = <<0, 1>>
    uuid     = "00010203-0405-4607-8809-0a0b0c0d0e0f"
    datetime = ~N[2014-01-16 20:26:51]

    TestRepo.insert!(%Post{blob: blob, public: true, visits: integer, uuid: uuid,
                           counter: integer, inserted_at: datetime, intensity: float})

    # nil
    assert [nil] = TestRepo.all(from Post, select: nil)

    # ID
    assert [1] = TestRepo.all(from p in Post, where: p.counter == ^integer, select: p.counter)

    # Integers
    assert [1] = TestRepo.all(from p in Post, where: p.visits == ^integer, select: p.visits)
    assert [1] = TestRepo.all(from p in Post, where: p.visits == 1, select: p.visits)
    assert [3] = TestRepo.all(from p in Post, select: p.visits + 2)

    # Floats
    assert [0.1] = TestRepo.all(from p in Post, where: p.intensity == ^float, select: p.intensity)
    assert [0.1] = TestRepo.all(from p in Post, where: p.intensity == 0.1, select: p.intensity)
    assert [1500.0] = TestRepo.all(from p in Post, select: 1500.0)
    assert [0.5] = TestRepo.all(from p in Post, select: p.intensity * 5)

    # Booleans
    assert [true] = TestRepo.all(from p in Post, where: p.public == ^true, select: p.public)
    assert [true] = TestRepo.all(from p in Post, where: p.public == true, select: p.public)

    # Binaries
    assert [^blob] = TestRepo.all(from p in Post, where: p.blob == <<0, 1>>, select: p.blob)
    assert [^blob] = TestRepo.all(from p in Post, where: p.blob == ^blob, select: p.blob)

    # UUID
    assert [^uuid] = TestRepo.all(from p in Post, where: p.uuid == ^uuid, select: p.uuid)

    # NaiveDatetime
    assert [^datetime] = TestRepo.all(from p in Post, where: p.inserted_at == ^datetime, select: p.inserted_at)

    # Datetime
    datetime = DateTime.from_unix!(System.os_time(:second), :second)
    TestRepo.insert!(%User{inserted_at: datetime})
    assert [^datetime] = TestRepo.all(from u in User, where: u.inserted_at == ^datetime, select: u.inserted_at)

    # usec
    naive_datetime = ~N[2014-01-16 20:26:51.000000]
    datetime = DateTime.from_naive!(~N[2014-01-16 20:26:51.000000], "Etc/UTC")
    TestRepo.insert!(%Usec{naive_datetime_usec: naive_datetime, utc_datetime_usec: datetime})
    assert [^naive_datetime] = TestRepo.all(from u in Usec, where: u.naive_datetime_usec == ^naive_datetime, select: u.naive_datetime_usec)
    assert [^datetime] = TestRepo.all(from u in Usec, where: u.utc_datetime_usec == ^datetime, select: u.utc_datetime_usec)

    naive_datetime = ~N[2014-01-16 20:26:51.123000]
    datetime = DateTime.from_naive!(~N[2014-01-16 20:26:51.123000], "Etc/UTC")
    TestRepo.insert!(%Usec{naive_datetime_usec: naive_datetime, utc_datetime_usec: datetime})
    assert [^naive_datetime] = TestRepo.all(from u in Usec, where: u.naive_datetime_usec == ^naive_datetime, select: u.naive_datetime_usec)
    assert [^datetime] = TestRepo.all(from u in Usec, where: u.utc_datetime_usec == ^datetime, select: u.utc_datetime_usec)
  end

  @tag :select_not
  test "primitive types boolean negate" do
    TestRepo.insert!(%Post{public: true})
    assert [false] = TestRepo.all(from p in Post, where: p.public == true, select: not p.public)
    assert [true] = TestRepo.all(from p in Post, where: p.public == true, select: not not p.public)
  end

  test "aggregate types" do
    datetime = ~N[2014-01-16 20:26:51]
    TestRepo.insert!(%Post{inserted_at: datetime})
    query = from p in Post, select: max(p.inserted_at)
    assert [^datetime] = TestRepo.all(query)
  end

  # We don't specifically assert on the tuple content because
  # some databases would return integer, others decimal.
  # The important is that the type has been invoked for wrapping.
  test "aggregate custom types" do
    TestRepo.insert!(%Post{wrapped_visits: {:int, 10}})
    query = from p in Post, select: sum(p.wrapped_visits)
    assert [{:int, _}] = TestRepo.all(query)
  end

  @tag :aggregate_filters
  test "aggregate filter types" do
    datetime = ~N[2014-01-16 20:26:51]
    TestRepo.insert!(%Post{inserted_at: datetime})
    query = from p in Post, select: filter(max(p.inserted_at), p.public == ^true)
    assert [^datetime] = TestRepo.all(query)
  end

  test "coalesce text type when default" do
    TestRepo.insert!(%Post{blob: nil})
    blob = <<0, 1>>
    query = from p in Post, select: coalesce(p.blob, ^blob)
    assert [^blob] = TestRepo.all(query)
  end

  test "coalesce text type when value" do
    blob = <<0, 2>>
    default_blob = <<0, 1>>
    TestRepo.insert!(%Post{blob: blob})
    query = from p in Post, select: coalesce(p.blob, ^default_blob)
    assert [^blob] = TestRepo.all(query)
  end

  test "tagged types" do
    TestRepo.insert!(%Post{})

    # Numbers
    assert [1]   = TestRepo.all(from Post, select: type(^"1", :integer))
    assert [1.0] = TestRepo.all(from Post, select: type(^1.0, :float))
    assert [1]   = TestRepo.all(from p in Post, select: type(^"1", p.visits))
    assert [1.0] = TestRepo.all(from p in Post, select: type(^"1", p.intensity))

    # Custom wrappers
    assert [1] = TestRepo.all(from Post, select: type(^"1", CustomPermalink))

    # Custom types
    uuid = Ecto.UUID.generate()
    assert [^uuid] = TestRepo.all(from Post, select: type(^uuid, Ecto.UUID))

    # Math operations
    assert [4]   = TestRepo.all(from Post, select: type(2 + ^"2", :integer))
    assert [4.0] = TestRepo.all(from Post, select: type(2.0 + ^"2", :float))
    assert [4]   = TestRepo.all(from p in Post, select: type(2 + ^"2", p.visits))
    assert [4.0] = TestRepo.all(from p in Post, select: type(2.0 + ^"2", p.intensity))
  end

  test "binary id type" do
    assert %Custom{} = custom = TestRepo.insert!(%Custom{})
    bid = custom.bid
    assert [^bid] = TestRepo.all(from c in Custom, select: c.bid)
    assert [^bid] = TestRepo.all(from c in Custom, select: type(^bid, :binary_id))
  end

  @tag :like_match_blob
  test "text type as blob" do
    assert %Post{} = post = TestRepo.insert!(%Post{blob: <<0, 1, 2>>})
    id = post.id
    assert post.blob == <<0, 1, 2>>
    assert [^id] = TestRepo.all(from p in Post, where: like(p.blob, ^<<0, 1, 2>>), select: p.id)
  end

  @tag :like_match_blob
  @tag :text_type_as_string
  test "text type as string" do
    assert %Post{} = post = TestRepo.insert!(%Post{blob: "hello"})
    id = post.id
    assert post.blob == "hello"
    assert [^id] = TestRepo.all(from p in Post, where: like(p.blob, ^"hello"), select: p.id)
  end

  @tag :array_type
  test "array type" do
    ints = [1, 2, 3]
    tag = TestRepo.insert!(%Tag{ints: ints})

    assert TestRepo.all(from t in Tag, where: t.ints == ^[], select: t.ints) == []
    assert TestRepo.all(from t in Tag, where: t.ints == ^[1, 2, 3], select: t.ints) == [ints]

    # Both sides interpolation
    assert TestRepo.all(from t in Tag, where: ^"b" in ^["a", "b", "c"], select: t.ints) == [ints]
    assert TestRepo.all(from t in Tag, where: ^"b" in [^"a", ^"b", ^"c"], select: t.ints) == [ints]

    # Querying
    assert TestRepo.all(from t in Tag, where: t.ints == [1, 2, 3], select: t.ints) == [ints]
    assert TestRepo.all(from t in Tag, where: 0 in t.ints, select: t.ints) == []
    assert TestRepo.all(from t in Tag, where: 1 in t.ints, select: t.ints) == [ints]

    # Update
    tag = TestRepo.update!(Ecto.Changeset.change tag, ints: nil)
    assert TestRepo.get!(Tag, tag.id).ints == nil

    tag = TestRepo.update!(Ecto.Changeset.change tag, ints: [3, 2, 1])
    assert TestRepo.get!(Tag, tag.id).ints == [3, 2, 1]

    # Update all
    {1, _} = TestRepo.update_all(Tag, push: [ints: 0])
    assert TestRepo.get!(Tag, tag.id).ints == [3, 2, 1, 0]

    {1, _} = TestRepo.update_all(Tag, pull: [ints: 2])
    assert TestRepo.get!(Tag, tag.id).ints == [3, 1, 0]

    {1, _} = TestRepo.update_all(Tag, set: [ints: nil])
    assert TestRepo.get!(Tag, tag.id).ints == nil
  end

  @tag :array_type
  test "array type with custom types" do
    uuids = ["51fcfbdd-ad60-4ccb-8bf9-47aabd66d075"]
    TestRepo.insert!(%Tag{uuids: ["51fcfbdd-ad60-4ccb-8bf9-47aabd66d075"]})

    assert TestRepo.all(from t in Tag, where: t.uuids == ^[], select: t.uuids) == []
    assert TestRepo.all(from t in Tag, where: t.uuids == ^["51fcfbdd-ad60-4ccb-8bf9-47aabd66d075"],
                                       select: t.uuids) == [uuids]

    {1, _} = TestRepo.update_all(Tag, set: [uuids: nil])
    assert TestRepo.all(from t in Tag, select: t.uuids) == [nil]
  end

  @tag :array_type
  test "array type with nil in array" do
    tag = TestRepo.insert!(%Tag{ints: [1, nil, 3]})
    assert tag.ints == [1, nil, 3]
  end

  @tag :map_type
  test "untyped map" do
    post1 = TestRepo.insert!(%Post{meta: %{"foo" => "bar", "baz" => "bat"}})
    post2 = TestRepo.insert!(%Post{meta: %{foo: "bar", baz: "bat"}})

    assert TestRepo.all(from p in Post, where: p.id == ^post1.id, select: p.meta) ==
           [%{"foo" => "bar", "baz" => "bat"}]
    assert TestRepo.all(from p in Post, where: p.id == ^post2.id, select: p.meta) ==
           [%{"foo" => "bar", "baz" => "bat"}]
  end

  @tag :map_type
  test "typed string map" do
    post1 = TestRepo.insert!(%Post{links: %{"foo" => "http://foo.com", "bar" => "http://bar.com"}})
    post2 = TestRepo.insert!(%Post{links: %{foo: "http://foo.com", bar: "http://bar.com"}})

    assert TestRepo.all(from p in Post, where: p.id == ^post1.id, select: p.links) ==
           [%{"foo" => "http://foo.com", "bar" => "http://bar.com"}]
    assert TestRepo.all(from p in Post, where: p.id == ^post2.id, select: p.links) ==
           [%{"foo" => "http://foo.com", "bar" => "http://bar.com"}]
  end

  @tag :map_type
  test "typed float map" do
    post = TestRepo.insert!(%Post{intensities: %{"foo" => 1.0, "bar" => 416500.0}})

    # Note we are using === since we want to check integer vs float
    assert TestRepo.all(from p in Post, where: p.id == ^post.id, select: p.intensities) ===
           [%{"foo" => 1.0, "bar" => 416500.0}]
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
    item = %Item{price: 123, valid_at: ~D[2014-01-16]}

    order =
      %Order{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:item, item)
      |> TestRepo.insert!()

    dbitem = TestRepo.get!(Order, order.id).item
    assert item.reference == dbitem.reference
    assert item.price == dbitem.price
    assert item.valid_at == dbitem.valid_at
    assert dbitem.id

    [dbitem] = TestRepo.all(from o in Order, select: o.item)
    assert item.reference == dbitem.reference
    assert item.price == dbitem.price
    assert item.valid_at == dbitem.valid_at
    assert dbitem.id

    {1, _} = TestRepo.update_all(Order, set: [item: %{dbitem | price: 456}])
    assert TestRepo.get!(Order, order.id).item.price == 456
  end

  @tag :map_type
  @tag :json_extract_path
  test "json_extract_path with primitive values" do
    order = %Order{meta: %{:id => 123, :time => ~T[09:00:00], "'single quoted'" => "bar", "\"double quoted\"" => "baz"}}
    TestRepo.insert!(order)

    assert TestRepo.one(from o in Order, select: o.meta["id"]) == 123
    assert TestRepo.one(from o in Order, select: o.meta["bad"]) == nil
    assert TestRepo.one(from o in Order, select: o.meta["bad"]["bad"]) == nil

    field = "id"
    assert TestRepo.one(from o in Order, select: o.meta[^field]) == 123
    assert TestRepo.one(from o in Order, select: o.meta["time"]) == "09:00:00"
    assert TestRepo.one(from o in Order, select: o.meta["'single quoted'"]) == "bar"
    assert TestRepo.one(from o in Order, select: o.meta["';"]) == nil
    assert TestRepo.one(from o in Order, select: o.meta["\"double quoted\""]) == "baz"
  end

  @tag :map_type
  @tag :json_extract_path
  test "json_extract_path with arrays and objects" do
    order = %Order{meta: %{tags: [%{name: "red"}, %{name: "green"}]}}
    TestRepo.insert!(order)

    assert TestRepo.one(from o in Order, select: o.meta["tags"][0]["name"]) == "red"
    assert TestRepo.one(from o in Order, select: o.meta["tags"][99]["name"]) == nil

    index = 1
    assert TestRepo.one(from o in Order, select: o.meta["tags"][^index]["name"]) == "green"
  end

  @tag :map_type
  @tag :json_extract_path
  test "json_extract_path with embeds" do
    order = %Order{items: [%{valid_at: ~D[2020-01-01]}]}
    TestRepo.insert!(order)

    assert TestRepo.one(from o in Order, select: o.items[0]["valid_at"]) == "2020-01-01"
  end

  @tag :map_type
  @tag :map_type_schemaless
  test "embeds one with custom type" do
    item = %Item{price: 123, reference: "PREFIX-EXAMPLE"}

    order =
      %Order{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:item, item)
      |> TestRepo.insert!()

    dbitem = TestRepo.get!(Order, order.id).item
    assert dbitem.reference == "PREFIX-EXAMPLE"
    assert [%{"reference" => "EXAMPLE"}] = TestRepo.all(from o in "orders", select: o.item)
  end

  @tag :map_type
  test "empty embeds one" do
    order = TestRepo.insert!(%Order{})
    assert order.item == nil
    assert TestRepo.get!(Order, order.id).item == nil
  end

  @tag :map_type
  @tag :array_type
  test "embeds many" do
    item = %Item{price: 123, valid_at: ~D[2014-01-16]}
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

  @tag :map_type
  @tag :array_type
  test "empty embeds many" do
    tag = TestRepo.insert!(%Tag{})
    assert tag.items == []
    assert TestRepo.get!(Tag, tag.id).items == []
  end

  @tag :map_type
  @tag :array_type
  test "nested embeds" do
    red = %ItemColor{name: "red"}
    blue = %ItemColor{name: "blue"}
    item = %Item{
      primary_color: red,
      secondary_colors: [blue]
    }

    order =
      %Order{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:item, item)
    order = TestRepo.insert!(order)

    dbitem = TestRepo.get!(Order, order.id).item
    assert dbitem.primary_color.name == "red"
    assert Enum.map(dbitem.secondary_colors, & &1.name) == ["blue"]
    assert dbitem.id
    assert dbitem.primary_color.id

    [dbitem] = TestRepo.all(from o in Order, select: o.item)
    assert dbitem.primary_color.name == "red"
    assert Enum.map(dbitem.secondary_colors, & &1.name) == ["blue"]
    assert dbitem.id
    assert dbitem.primary_color.id
  end

  @tag :decimal_type
  test "decimal type" do
    decimal = Decimal.new("1.0")
    TestRepo.insert!(%Post{cost: decimal})

    [cost] = TestRepo.all(from p in Post, where: p.cost == ^decimal, select: p.cost)
    assert Decimal.equal?(decimal, cost)
    [cost] = TestRepo.all(from p in Post, where: p.cost == ^1.0, select: p.cost)
    assert Decimal.equal?(decimal, cost)
    [cost] = TestRepo.all(from p in Post, where: p.cost == ^1, select: p.cost)
    assert Decimal.equal?(decimal, cost)
    [cost] = TestRepo.all(from p in Post, where: p.cost == 1.0, select: p.cost)
    assert Decimal.equal?(decimal, cost)
    [cost] = TestRepo.all(from p in Post, where: p.cost == 1, select: p.cost)
    assert Decimal.equal?(decimal, cost)
    [cost] = TestRepo.all(from p in Post, select: p.cost * 2)
    assert Decimal.equal?(Decimal.new("2.0"), cost)
    [cost] = TestRepo.all(from p in Post, select: p.cost - p.cost)
    assert Decimal.equal?(Decimal.new("0.0"), cost)
  end

  @tag :decimal_type
  @tag :decimal_precision
  test "decimal typed aggregations" do
    decimal = Decimal.new("1.0")
    TestRepo.insert!(%Post{cost: decimal})

    assert [1] = TestRepo.all(from p in Post, select: type(sum(p.cost), :integer))
    assert [1.0] = TestRepo.all(from p in Post, select: type(sum(p.cost), :float))
    [cost] = TestRepo.all(from p in Post, select: type(sum(p.cost), :decimal))
    assert Decimal.equal?(decimal, cost)
  end

  @tag :decimal_type
  test "on coalesce with mixed types" do
    decimal = Decimal.new("1.0")
    TestRepo.insert!(%Post{cost: decimal})
    [cost] = TestRepo.all(from p in Post, select: coalesce(p.cost, 0))
    assert Decimal.equal?(decimal, cost)
  end

  @tag :union_with_literals
  test "unions with literals" do
    TestRepo.insert!(%Post{})
    TestRepo.insert!(%Post{})

    query1 = from(p in Post, select: %{n: 1})
    query2 = from(p in Post, select: %{n: 2})

    assert TestRepo.all(union_all(query1, ^query2)) ==
            [%{n: 1}, %{n: 1}, %{n: 2}, %{n: 2}]

    query1 = from(p in Post, select: %{n: 1.0})
    query2 = from(p in Post, select: %{n: 2.0})

    assert TestRepo.all(union_all(query1, ^query2)) ==
            [%{n: 1.0}, %{n: 1.0}, %{n: 2.0}, %{n: 2.0}]

    query1 = from(p in Post, select: %{n: "foo"})
    query2 = from(p in Post, select: %{n: "bar"})

    assert TestRepo.all(union_all(query1, ^query2)) ==
            [%{n: "foo"}, %{n: "foo"}, %{n: "bar"}, %{n: "bar"}]
  end

  test "schemaless types" do
    TestRepo.insert!(%Post{visits: 123})
    assert [123] = TestRepo.all(from p in "posts", select: type(p.visits, :integer))
  end

  test "schemaless calendar types" do
    datetime = ~N[2014-01-16 20:26:51]
    assert {1, _} =
           TestRepo.insert_all("posts", [[inserted_at: datetime]])
    assert {1, _} =
           TestRepo.update_all("posts", set: [inserted_at: datetime])
    assert [_] =
           TestRepo.all(from p in "posts", where: p.inserted_at >= ^datetime, select: p.inserted_at)
    assert [_] =
           TestRepo.all(from p in "posts", where: p.inserted_at in [^datetime], select: p.inserted_at)
    assert [_] =
           TestRepo.all(from p in "posts", where: p.inserted_at in ^[datetime], select: p.inserted_at)
  end
end
