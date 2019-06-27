defmodule BotanyTest do
  use ExUnit.Case
  doctest Botany

  test "greets the world" do
    assert Botany.hello() == :world
  end
end
