
defmodule Custom.Permalink do
  def type, do: :integer

  def cast(string) when is_binary(string) do
    case Integer.parse(string) do
      {int, _} -> {:ok, int}
      :error   -> :error
    end
  end

  def cast(integer) when is_integer(integer), do: {:ok, integer}

  def cast(_), do: :error
  def blank?(_), do: false

  def load(integer) when is_integer(integer), do: {:ok, integer}
  def dump(integer) when is_integer(integer), do: {:ok, integer}
end

defmodule Custom.DateTime do
  defstruct [:year, :month, :day, :hour, :min, :sec]

  def blank?(_), do: false
  def type, do: :datetime

  def cast(%Custom.DateTime{} = datetime), do: {:ok, datetime}
  def cast(_), do: :error

  def load({{year, month, day}, {hour, min, sec}}) do
    {:ok, %Custom.DateTime{year: year, month: month, day: day,
                           hour: hour, min: min, sec: sec}}
  end

  def dump(%Custom.DateTime{} = dt) do
    {:ok, {{dt.year, dt.month, dt.day}, {dt.hour, dt.min, dt.sec}}}
  end
end
