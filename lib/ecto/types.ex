defrecord Ecto.Date, [:year, :month, :day] do
  def to_erl(Ecto.Date[] = d) do
    {d.year, d.month, d.day}
  end

  def from_erl({year, month, day}) do
    Ecto.Date[year: year, month: month, day: day]
  end
end

defrecord Ecto.Time, [:hour, :min, :sec] do
  def to_erl(Ecto.Time[] = t) do
    {t.hour, t.min, t.sec}
  end

  def from_erl({hour, min, sec}) do
    Ecto.Time[hour: hour, min: min, sec: sec]
  end
end

defrecord Ecto.DateTime, [:year, :month, :day, :hour, :min, :sec] do
  def to_erl(Ecto.DateTime[] = dt) do
    {{dt.year, dt.month, dt.day}, {dt.hour, dt.min, dt.sec}}
  end

  def from_erl({{year, month, day}, {hour, min, sec}}) do
    Ecto.DateTime[year: year, month: month, day: day,
                  hour: hour, min: min, sec: sec]
  end

  def to_date(Ecto.DateTime[] = dt) do
    Ecto.Date[year: dt.year, month: dt.month, day: dt.day]
  end

  def to_time(Ecto.Time[] = dt) do
    Ecto.Time[hour: dt.hour, min: dt.min, sec: dt.sec]
  end

  def from_date_time(Ecto.Date[] = d, Ecto.Time[] = t) do
    Ecto.DateTime[year: d.year, month: d.month, day: d.day,
                  hour: t.hour, min: t.min, sec: t.sec]
  end
end

defrecord Ecto.Interval, [:year, :month, :day, :hour, :min, :sec]

defrecord Ecto.Binary, [:value] do
  @moduledoc false
end

defrecord Ecto.Array, [:value, :type] do
  @moduledoc false
end
