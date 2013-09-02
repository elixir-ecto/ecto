defmodule Ecto do
  defrecord DateTime, [:year, :month, :day, :hour, :min, :sec]
  defrecord Interval, [:year, :month, :day, :hour, :min, :sec]
end
