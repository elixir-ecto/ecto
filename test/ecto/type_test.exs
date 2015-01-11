defmodule Ecto.TypeTest do
  use ExUnit.Case, async: true

  import Kernel, except: [match?: 2], warn: false
  import Ecto.Type
  doctest Ecto.Type

  @behaviour Ecto.Type
  def type,      do: :custom
  def load(_),   do: {:ok, :load}
  def dump(_),   do: {:ok, :dump}
  def cast(_),   do: {:ok, :cast}
  def blank?(_), do: false

  test "custom types" do
    assert load(__MODULE__, "foo") == {:ok, :load}
    assert dump(__MODULE__, "foo") == {:ok, :dump}
    assert cast(__MODULE__, "foo") == {:ok, :cast}
    refute blank?(__MODULE__, "foo")

    assert load(__MODULE__, nil) == {:ok, nil}
    assert dump(__MODULE__, nil) == {:ok, nil}
    assert cast(__MODULE__, nil) == {:ok, nil}
    assert blank?(__MODULE__, nil)
  end
end
