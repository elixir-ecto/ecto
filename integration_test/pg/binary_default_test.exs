defmodule Ecto.Integration.BinaryDefaultTest do
  # Cannot be async as other tests may migrate
  use ExUnit.Case

  alias Ecto.Integration.PoolRepo

  defmodule BinaryDefaultMigration do
    use Ecto.Migration

    def up do
      create table(:binary_default_migration) do
        add(:value, :binary, default: <<0, 0>>)
      end
    end

    def down do
      drop(table(:binary_default_migration))
    end
  end

  import Ecto.Migrator, only: [up: 4, down: 4]

  @tag :set_default_for_binary_column
  test "set default for binary column" do
    assert :ok == up(PoolRepo, 20151012120000, BinaryDefaultMigration, log: false)
    assert :ok == down(PoolRepo, 20151012120000, BinaryDefaultMigration, log: false)
  end
end
