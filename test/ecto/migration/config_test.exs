defmodule Ecto.Migration.ConfigTest do
  use ExUnit.Case, async: true

  import Ecto.Migration.Config

  defp put_env(env) do
    Application.put_env(:ecto, :ecto_migration, env)
  end

  test "primary key should have default" do
    Application.delete_env(:ecto, :ecto_migration)
    assert primary_key == {:version, :integer, []}
    assert primary_key_column(:type) == :bigint
  end

  test "primary key should be sourced from config" do
    custom_primary_key = {:version, :string, []}
    put_env(primary_key: custom_primary_key)

    assert primary_key == custom_primary_key
  end

  test "returns column name of primary key" do
    put_env(primary_key: {:custom_primary_key, :string, []})

    assert primary_key_column(:name) == :custom_primary_key
  end

  test "returns column type of primary key" do
    put_env(primary_key: {:custom_primary_key, :string, []})

    assert primary_key_column(:type) == :string

    put_env(primary_key: {:custom_primary_key, :integer, []})

    assert primary_key_column(:type) == :bigint
  end
end
