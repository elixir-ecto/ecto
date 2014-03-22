defmodule Ecto.Integration.TypesTest do
  use Ecto.Integration.Postgres.Case

  test "datetime type" do
    now = Ecto.DateTime[year: 2013, month: 8, day: 1, hour: 14, min: 28, sec: 0]
    c = TestRepo.create(Comment.Entity[posted: now])

    assert Comment.Entity[posted: ^now] = TestRepo.get(Comment, c.id)
  end

  test "date type" do
    now = Ecto.Date[year: 2013, month: 8, day: 1]
    c = TestRepo.create(Comment.Entity[day: now])

    assert Comment.Entity[day: ^now] = TestRepo.get(Comment, c.id)
  end

  test "time type" do
    now = Ecto.Time[hour: 14, min: 28, sec: 0]
    c = TestRepo.create(Comment.Entity[time: now])

    assert Comment.Entity[time: ^now] = TestRepo.get(Comment, c.id)
  end

  test "interval type" do
    interval = Ecto.Interval[year: 2013, month: 8, day: 1, hour: 14, min: 28, sec: 0]
    c = TestRepo.create(Comment.Entity[interval: interval])

    assert Comment.Entity[interval: Ecto.Interval[]] = TestRepo.get(Comment, c.id)
  end

  test "binary type is hidden" do
    binary = << 0, 1, 2, 3, 4 >>
    c = TestRepo.create(Comment.Entity[bytes: binary])

    assert ^binary = TestRepo.get(Comment, c.id).bytes
  end
end
