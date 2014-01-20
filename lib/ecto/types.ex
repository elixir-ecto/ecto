defrecord Ecto.DateTime, [:year, :month, :day, :hour, :min, :sec] do
  def to_erl(Ecto.DateTime[] = dt) do
    { { dt.year, dt.month, dt.day }, { dt.hour, dt.min, dt.sec } }
  end

  def from_erl({ { year, month, day }, { hour, min, sec } }) do
    Ecto.DateTime[year: year, month: month, day: day,
                  hour: hour, min: min, sec: sec]
  end
end

defrecord Ecto.Interval, [:year, :month, :day, :hour, :min, :sec]

defrecord Ecto.Binary, [:value] do
  @moduledoc false
end

defrecord Ecto.Array, [:value, :type] do
  @moduledoc false
end
