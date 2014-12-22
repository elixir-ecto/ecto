defmodule Ecto.Integration.TypesTest do
  use Ecto.Integration.Postgres.Case

  test "datetime type" do
    now = %Ecto.DateTime{year: 2013, month: 8, day: 1, hour: 14, min: 28, sec: 0}
    c = TestRepo.insert(%Comment{posted: now})

    assert %Comment{posted: ^now} = TestRepo.get(Comment, c.id)
  end

  test "date type" do
    now = %Ecto.Date{year: 2013, month: 8, day: 1}
    c = TestRepo.insert(%Comment{day: now})

    assert %Comment{day: ^now} = TestRepo.get(Comment, c.id)
  end

  test "time type" do
    now = %Ecto.Time{hour: 14, min: 28, sec: 0}
    c = TestRepo.insert(%Comment{time: now})

    assert %Comment{time: ^now} = TestRepo.get(Comment, c.id)
  end

  test "binary type is hidden" do
    binary = <<0, 1, 2, 3, 4>>
    c = TestRepo.insert(%Comment{bytes: binary})

    assert ^binary = TestRepo.get(Comment, c.id).bytes
  end

  test "uuid type" do
    uuid = <<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>

    p = TestRepo.insert(%Post{uuid: uuid})
    assert ^uuid = TestRepo.get(Post, p.id).uuid

    TestRepo.insert(%UUIDPrimaryKey{id: uuid})
    assert ^uuid = TestRepo.get(UUIDPrimaryKey, uuid).id
  end
end
