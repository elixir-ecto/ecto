defmodule Ecto.Integration.DateTime do
  def round_datetime_if_needed(element, false), do: apply_datetime_rounding(element)
  def round_datetime_if_needed(element, true), do: element

  # take for instance a post and apply mysql rounding to inserted_at and updated_at
  defp apply_datetime_rounding(element) do
    %{element | inserted_at: datetime_rounding(element.inserted_at),
                updated_at:  datetime_rounding(element.updated_at)}
  end
  # Sets usec to 0. This is how MySQl 5.5 does it. MySQL 5.6 will also round up seconds if usec >= 500000
  defp datetime_rounding(%Ecto.DateTime{day: day, hour: hour, min: min, month: month, sec: sec, usec: _usec, year: year}) do
    %Ecto.DateTime{day: day, hour: hour, min: min, month: month, sec: sec, usec: 0, year: year}
  end
end
