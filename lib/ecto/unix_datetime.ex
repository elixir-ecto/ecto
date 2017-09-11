defmodule MyApp.UnixDateTime do
  @moduledoc """
  An Ecto type for Date Time stored in DB as integer produced by unix `date +%s` command
  """

  @behaviour Ecto.Type

  def handles_nil?(), do: true

  @doc """
  The Ecto type.
  """
  def type, do: __MODULE__

  @doc """
  Casts to __MODULE__.
  """
  @spec cast(t | any) :: {:ok, t} | :error
  def cast(%DateTime{} = date), do: {:ok, date}

  def cast(_), do: :error

  @doc """
  Converts a string representing a UUID into a binary.
  """
  @spec dump(t | any) :: {:ok, integer} | :error
  def dump(%DateTime{} = date), do: {:ok, DateTime.to_unix(date)}
  # Write 0 for no value
  def dump(nil), do: {:ok, 0}

  def dump(_), do: :error

  @doc """
  Converts an Integer into DateTime.
  """
  @spec load(integer) :: {:ok, t} | :error
  def load(value) when is_integer(value) do
    {:ok, DateTime.from_unix!(value)}
  end
  # If DB contains 0 this means Date has a default value
  # and it's blank - having nil value
  def load(0), do: {:ok, nil}
  def load(_), do: :error

end
