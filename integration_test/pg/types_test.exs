defmodule Ecto.Integration.TypesTest do
  use Ecto.Integration.Postgres.Case

  test "datetime type" do
    now = Ecto.DateTime[year: 2013, month: 8, day: 1, hour: 14, min: 28, sec: 0]
    c = TestRepo.create(Comment.Entity[posted: now])

    assert Comment.Entity[posted: ^now] = TestRepo.get(Comment, c.id)
  end

  test "interval type" do
    interval = Ecto.Interval[year: 2013, month: 8, day: 1, hour: 14, min: 28, sec: 0]
    c = TestRepo.create(Comment.Entity[interval: interval])

    assert Comment.Entity[interval: Ecto.Interval[]] = TestRepo.get(Comment, c.id)
  end

  test "binary type" do
    binary = Ecto.Binary[value: << 0, 1, 2, 3, 4 >>]
    c = TestRepo.create(Comment.Entity[bytes: binary])

    assert Comment.Entity[bytes: ^binary] = TestRepo.get(Comment, c.id)
  end
end
