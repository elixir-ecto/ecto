defmodule Ecto.Integration.IntervalTest do
  use Ecto.Integration.Case, async: Application.compile_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.{Post, User, Usec}
  alias Ecto.Integration.TestRepo
  import Ecto.Query

  @posted ~D[2014-01-01]
  @inserted_at ~N[2014-01-01 02:00:00]

  setup do
    TestRepo.insert!(%Post{posted: @posted, inserted_at: @inserted_at})
    :ok
  end

  test "date_add with year" do
    dec = Decimal.new(1)
    assert [~D[2015-01-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, 1, "year"))
    assert [~D[2015-01-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, 1.0, "year"))
    assert [~D[2015-01-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^1, "year"))
    assert [~D[2015-01-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^1.0, "year"))
    assert [~D[2015-01-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^dec, "year"))
  end

  test "date_add with month" do
    dec = Decimal.new(3)
    assert [~D[2014-04-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, 3, "month"))
    assert [~D[2014-04-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, 3.0, "month"))
    assert [~D[2014-04-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^3, "month"))
    assert [~D[2014-04-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^3.0, "month"))
    assert [~D[2014-04-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^dec, "month"))
  end

  test "date_add with week" do
    dec = Decimal.new(3)
    assert [~D[2014-01-22]] = TestRepo.all(from p in Post, select: date_add(p.posted, 3, "week"))
    assert [~D[2014-01-22]] = TestRepo.all(from p in Post, select: date_add(p.posted, 3.0, "week"))
    assert [~D[2014-01-22]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^3, "week"))
    assert [~D[2014-01-22]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^3.0, "week"))
    assert [~D[2014-01-22]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^dec, "week"))
  end

  test "date_add with day" do
    dec = Decimal.new(5)
    assert [~D[2014-01-06]] = TestRepo.all(from p in Post, select: date_add(p.posted, 5, "day"))
    assert [~D[2014-01-06]] = TestRepo.all(from p in Post, select: date_add(p.posted, 5.0, "day"))
    assert [~D[2014-01-06]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^5, "day"))
    assert [~D[2014-01-06]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^5.0, "day"))
    assert [~D[2014-01-06]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^dec, "day"))
  end

  test "date_add with hour" do
    dec = Decimal.new(48)
    assert [~D[2014-01-03]] = TestRepo.all(from p in Post, select: date_add(p.posted, 48, "hour"))
    assert [~D[2014-01-03]] = TestRepo.all(from p in Post, select: date_add(p.posted, 48.0, "hour"))
    assert [~D[2014-01-03]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^48, "hour"))
    assert [~D[2014-01-03]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^48.0, "hour"))
    assert [~D[2014-01-03]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^dec, "hour"))
  end

  test "date_add with dynamic" do
    posted = @posted
    assert [~D[2015-01-01]]  = TestRepo.all(from p in Post, select: date_add(^posted, ^1, ^"year"))
    assert [~D[2014-04-01]]  = TestRepo.all(from p in Post, select: date_add(^posted, ^3, ^"month"))
    assert [~D[2014-01-22]] = TestRepo.all(from p in Post, select: date_add(^posted, ^3, ^"week"))
    assert [~D[2014-01-06]]  = TestRepo.all(from p in Post, select: date_add(^posted, ^5, ^"day"))
    assert [~D[2014-01-03]]  = TestRepo.all(from p in Post, select: date_add(^posted, ^48, ^"hour"))
  end

  test "date_add with negative interval" do
    dec = Decimal.new(-1)
    assert [~D[2013-01-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, -1, "year"))
    assert [~D[2013-01-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, -1.0, "year"))
    assert [~D[2013-01-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^-1, "year"))
    assert [~D[2013-01-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^-1.0, "year"))
    assert [~D[2013-01-01]] = TestRepo.all(from p in Post, select: date_add(p.posted, ^dec, "year"))
  end

  test "datetime_add with year" do
    dec = Decimal.new(1)
    assert [~N[2015-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 1, "year"))
    assert [~N[2015-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 1.0, "year"))
    assert [~N[2015-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^1, "year"))
    assert [~N[2015-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^1.0, "year"))
    assert [~N[2015-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^dec, "year"))
  end

  test "datetime_add with month" do
    dec = Decimal.new(3)
    assert [~N[2014-04-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 3, "month"))
    assert [~N[2014-04-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 3.0, "month"))
    assert [~N[2014-04-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^3, "month"))
    assert [~N[2014-04-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^3.0, "month"))
    assert [~N[2014-04-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^dec, "month"))
  end

  test "datetime_add with week" do
    dec = Decimal.new(3)
    assert [~N[2014-01-22 02:00:00]] =
            TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 3, "week"))
    assert [~N[2014-01-22 02:00:00]] =
            TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 3.0, "week"))
    assert [~N[2014-01-22 02:00:00]] =
            TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^3, "week"))
    assert [~N[2014-01-22 02:00:00]] =
            TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^3.0, "week"))
    assert [~N[2014-01-22 02:00:00]] =
            TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^dec, "week"))
  end

  test "datetime_add with day" do
    dec = Decimal.new(5)
    assert [~N[2014-01-06 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 5, "day"))
    assert [~N[2014-01-06 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 5.0, "day"))
    assert [~N[2014-01-06 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^5, "day"))
    assert [~N[2014-01-06 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^5.0, "day"))
    assert [~N[2014-01-06 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^dec, "day"))
  end

  test "datetime_add with hour" do
    dec = Decimal.new(60)
    assert [~N[2014-01-03 14:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 60, "hour"))
    assert [~N[2014-01-03 14:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 60.0, "hour"))
    assert [~N[2014-01-03 14:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^60, "hour"))
    assert [~N[2014-01-03 14:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^60.0, "hour"))
    assert [~N[2014-01-03 14:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^dec, "hour"))
  end

  test "datetime_add with minute" do
    dec = Decimal.new(90)
    assert [~N[2014-01-01 03:30:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 90, "minute"))
    assert [~N[2014-01-01 03:30:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 90.0, "minute"))
    assert [~N[2014-01-01 03:30:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^90, "minute"))
    assert [~N[2014-01-01 03:30:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^90.0, "minute"))
    assert [~N[2014-01-01 03:30:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^dec, "minute"))
  end

  test "datetime_add with second" do
    dec = Decimal.new(90)
    assert [~N[2014-01-01 02:01:30]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 90, "second"))
    assert [~N[2014-01-01 02:01:30]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 90.0, "second"))
    assert [~N[2014-01-01 02:01:30]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^90, "second"))
    assert [~N[2014-01-01 02:01:30]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^90.0, "second"))
    assert [~N[2014-01-01 02:01:30]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^dec, "second"))
  end

  @tag :uses_msec
  test "datetime_add with millisecond" do
    dec = Decimal.new(1500)
    assert [~N[2014-01-01 02:00:01]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 1500, "millisecond"))
    assert [~N[2014-01-01 02:00:01]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 1500.0, "millisecond"))
    assert [~N[2014-01-01 02:00:01]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^1500, "millisecond"))
    assert [~N[2014-01-01 02:00:01]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^1500.0, "millisecond"))
    assert [~N[2014-01-01 02:00:01]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^dec, "millisecond"))
  end

  @tag :microsecond_precision
  @tag :uses_usec
  test "datetime_add with microsecond" do
    dec = Decimal.new(1500)
    assert [~N[2014-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 1500, "microsecond"))
    assert [~N[2014-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, 1500.0, "microsecond"))
    assert [~N[2014-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^1500, "microsecond"))
    assert [~N[2014-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^1500.0, "microsecond"))
    assert [~N[2014-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^dec, "microsecond"))
  end

  test "datetime_add with dynamic" do
    inserted_at = @inserted_at
    assert [~N[2015-01-01 02:00:00]]  =
           TestRepo.all(from p in Post, select: datetime_add(^inserted_at, ^1, ^"year"))
    assert [~N[2014-04-01 02:00:00]]  =
           TestRepo.all(from p in Post, select: datetime_add(^inserted_at, ^3, ^"month"))
    assert [~N[2014-01-22 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(^inserted_at, ^3, ^"week"))
    assert [~N[2014-01-06 02:00:00]]  =
           TestRepo.all(from p in Post, select: datetime_add(^inserted_at, ^5, ^"day"))
    assert [~N[2014-01-03 14:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(^inserted_at, ^60, ^"hour"))
    assert [~N[2014-01-01 03:30:00]] =
           TestRepo.all(from p in Post, select: datetime_add(^inserted_at, ^90, ^"minute"))
    assert [~N[2014-01-01 02:01:30]] =
           TestRepo.all(from p in Post, select: datetime_add(^inserted_at, ^90, ^"second"))
  end

  test "datetime_add with dynamic in filters" do
    inserted_at = @inserted_at
    field = :inserted_at
    assert [_]  =
           TestRepo.all(from p in Post, where: p.inserted_at > datetime_add(^inserted_at, ^-1, "year"))
    assert [_]  =
           TestRepo.all(from p in Post, where: p.inserted_at > datetime_add(^inserted_at, -3, "month"))
    assert [_]  =
           TestRepo.all(from p in Post, where: field(p, ^field) > datetime_add(^inserted_at, ^-3, ^"week"))
    assert [_]  =
           TestRepo.all(from p in Post, where: field(p, ^field) > datetime_add(^inserted_at, -5, ^"day"))
  end

  test "datetime_add with negative interval" do
    dec = Decimal.new(-1)
    assert [~N[2013-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, -1, "year"))
    assert [~N[2013-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, -1.0, "year"))
    assert [~N[2013-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^-1, "year"))
    assert [~N[2013-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^-1.0, "year"))
    assert [~N[2013-01-01 02:00:00]] =
           TestRepo.all(from p in Post, select: datetime_add(p.inserted_at, ^dec, "year"))
  end

  test "from_now" do
    current = DateTime.utc_now().year
    dec = Decimal.new(5)
    assert [%{year: year}] = TestRepo.all(from p in Post, select: from_now(5, "year"))
    assert year > current
    assert [%{year: year}] = TestRepo.all(from p in Post, select: from_now(5.0, "year"))
    assert year > current
    assert [%{year: year}] = TestRepo.all(from p in Post, select: from_now(^5, "year"))
    assert year > current
    assert [%{year: year}] = TestRepo.all(from p in Post, select: from_now(^5.0, "year"))
    assert year > current
    assert [%{year: year}] = TestRepo.all(from p in Post, select: from_now(^dec, "year"))
    assert year > current
  end

  test "ago" do
    current = DateTime.utc_now().year
    dec = Decimal.new(5)
    assert [%{year: year}] = TestRepo.all(from p in Post, select: ago(5, "year"))
    assert year < current
    assert [%{year: year}] = TestRepo.all(from p in Post, select: ago(5.0, "year"))
    assert year < current
    assert [%{year: year}] = TestRepo.all(from p in Post, select: ago(^5, "year"))
    assert year < current
    assert [%{year: year}] = TestRepo.all(from p in Post, select: ago(^5.0, "year"))
    assert year < current
    assert [%{year: year}] = TestRepo.all(from p in Post, select: ago(^dec, "year"))
    assert year < current
  end

  test "datetime_add with utc_datetime" do
    {:ok, datetime} = DateTime.from_naive(@inserted_at, "Etc/UTC")
    TestRepo.insert!(%User{inserted_at: datetime})

    {:ok, datetime} = DateTime.from_naive(~N[2015-01-01 02:00:00], "Etc/UTC")
    dec = Decimal.new(1)

    assert [^datetime] =
           TestRepo.all(from p in User, select: datetime_add(type(^datetime, :utc_datetime), 0, "year"))
    assert [^datetime] =
           TestRepo.all(from p in User, select: datetime_add(p.inserted_at, 1, "year"))
    assert [^datetime] =
           TestRepo.all(from p in User, select: datetime_add(p.inserted_at, 1.0, "year"))
    assert [^datetime] =
           TestRepo.all(from p in User, select: datetime_add(p.inserted_at, ^1, "year"))
    assert [^datetime] =
           TestRepo.all(from p in User, select: datetime_add(p.inserted_at, ^1.0, "year"))
    assert [^datetime] =
           TestRepo.all(from p in User, select: datetime_add(p.inserted_at, ^dec, "year"))
  end

  @tag :microsecond_precision
  test "datetime_add with naive_datetime_usec" do
    TestRepo.insert!(%Usec{naive_datetime_usec: ~N[2014-01-01 02:00:00.000001]})
    datetime = ~N[2014-01-01 02:00:00.001501]

    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(type(^datetime, :naive_datetime_usec), 0, "microsecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.naive_datetime_usec, 1500, "microsecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.naive_datetime_usec, 1500.0, "microsecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.naive_datetime_usec, ^1500, "microsecond"))
  end

  @tag :microsecond_precision
  @tag :decimal_precision
  test "datetime_add with naive_datetime_usec and decimal increment" do
    TestRepo.insert!(%Usec{naive_datetime_usec: ~N[2014-01-01 02:00:00.000001]})
    dec = Decimal.new(1500)
    datetime = ~N[2014-01-01 02:00:00.001501]

    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.naive_datetime_usec, ^1500.0, "microsecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.naive_datetime_usec, ^dec, "microsecond"))
  end

  @tag :microsecond_precision
  test "datetime_add with utc_datetime_usec" do
    {:ok, datetime} = DateTime.from_naive(~N[2014-01-01 02:00:00.000001], "Etc/UTC")
    TestRepo.insert!(%Usec{utc_datetime_usec: datetime})

    {:ok, datetime} = DateTime.from_naive(~N[2014-01-01 02:00:00.001501], "Etc/UTC")

    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(type(^datetime, :utc_datetime_usec), 0, "microsecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.utc_datetime_usec, 1500, "microsecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.utc_datetime_usec, 1500.0, "microsecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.utc_datetime_usec, ^1500, "microsecond"))
  end

  @tag :microsecond_precision
  @tag :decimal_precision
  test "datetime_add uses utc_datetime_usec with decimal increment" do
    {:ok, datetime} = DateTime.from_naive(~N[2014-01-01 02:00:00.000001], "Etc/UTC")
    TestRepo.insert!(%Usec{utc_datetime_usec: datetime})

    {:ok, datetime} = DateTime.from_naive(~N[2014-01-01 02:00:00.001501], "Etc/UTC")
    dec = Decimal.new(1500)

    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.utc_datetime_usec, ^1500.0, "microsecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.utc_datetime_usec, ^dec, "microsecond"))
  end

  test "datetime_add with utc_datetime_usec in milliseconds" do
    {:ok, datetime} = DateTime.from_naive(~N[2014-01-01 02:00:00.001000], "Etc/UTC")
    TestRepo.insert!(%Usec{utc_datetime_usec: datetime})

    {:ok, datetime} = DateTime.from_naive(~N[2014-01-01 02:00:00.151000], "Etc/UTC")

    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(type(^datetime, :utc_datetime_usec), 0, "millisecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.utc_datetime_usec, 150, "millisecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.utc_datetime_usec, 150, "millisecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.utc_datetime_usec, ^150, "millisecond"))
  end

  @tag :decimal_precision
  test "datetime_add uses utc_datetime_usec with decimal increment in milliseconds" do
    {:ok, datetime} = DateTime.from_naive(~N[2014-01-01 02:00:00.001000], "Etc/UTC")
    TestRepo.insert!(%Usec{utc_datetime_usec: datetime})

    {:ok, datetime} = DateTime.from_naive(~N[2014-01-01 02:00:00.151000], "Etc/UTC")
    dec = Decimal.new(150)

    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.utc_datetime_usec, ^150.0, "millisecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.utc_datetime_usec, ^dec, "millisecond"))
  end

  test "datetime_add with naive_datetime_usec in milliseconds" do
    TestRepo.insert!(%Usec{naive_datetime_usec: ~N[2014-01-01 02:00:00.001000]})
    datetime = ~N[2014-01-01 02:00:00.151000]

    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(type(^datetime, :naive_datetime_usec), 0, "millisecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.naive_datetime_usec, 150, "millisecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.naive_datetime_usec, 150.0, "millisecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.naive_datetime_usec, ^150, "millisecond"))
  end

  @tag :decimal_precision
  test "datetime_add with naive_datetime_usec and decimal increment in milliseconds" do
    TestRepo.insert!(%Usec{naive_datetime_usec: ~N[2014-01-01 02:00:00.001000]})
    dec = Decimal.new(150)
    datetime = ~N[2014-01-01 02:00:00.151000]

    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.naive_datetime_usec, ^150.0, "millisecond"))
    assert [^datetime] =
           TestRepo.all(from u in Usec, select: datetime_add(u.naive_datetime_usec, ^dec, "millisecond"))
  end
end
