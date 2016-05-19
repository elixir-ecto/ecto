defmodule Mix.Tasks.EctoTest do
  use ExUnit.Case, async: true

  test "provide a list of available ecto mix tasks" do
    Mix.Tasks.Ecto.run []
    assert_received {:mix_shell, :info, ["Ecto v" <> _]}
    assert_received {:mix_shell, :info, ["mix ecto.create" <> _]}
    assert_received {:mix_shell, :info, ["mix ecto.drop" <> _]}
    assert_received {:mix_shell, :info, ["mix ecto.dump" <> _]}
    assert_received {:mix_shell, :info, ["mix ecto.gen.migration" <> _]}
    assert_received {:mix_shell, :info, ["mix ecto.gen.repo" <> _]}
    assert_received {:mix_shell, :info, ["mix ecto.load" <> _]}
    assert_received {:mix_shell, :info, ["mix ecto.migrate" <> _]}
    assert_received {:mix_shell, :info, ["mix ecto.rollback" <> _]}
  end

  test "expects no arguments" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Ecto.run ["invalid"]
    end
  end
end
