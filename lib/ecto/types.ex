defrecord Ecto.DateTime, [:year, :month, :day, :hour, :min, :sec]
defrecord Ecto.Interval, [:year, :month, :day, :hour, :min, :sec]

defrecord Ecto.Binary, [:value] do
  @moduledoc false
end
