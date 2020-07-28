defmodule Mix.Tasks.EctoTest do
  use ExUnit.Case

  test "provide a list of available Ecto Mix tasks" do
    Mix.Tasks.Ecto.run []
    assert_received {:mix_shell, :info, ["Ecto v" <> _]}
    assert_received {:mix_shell, :info, ["mix ecto.create" <> _]}
    assert_received {:mix_shell, :info, ["mix ecto.drop" <> _]}
    assert_received {:mix_shell, :info, ["mix ecto.gen.repo" <> _]}
  end

  test "expects no arguments" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Ecto.run ["invalid"]
    end
  end
end
