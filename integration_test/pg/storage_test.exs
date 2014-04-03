defmodule Ecto.Integration.StorageTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.Postgres

  def correct_params do
    [database: "storage_mgt",
     username: "postgres",
     password: "postgres",
     hostname: "localhost"]
  end

  def wrong_user do
    [database: "storage_mgt",
     username: "randomuser",
     password: "password1234",
     hostname: "localhost"]
  end

  def drop_database do
    System.cmd ~s(psql -U postgres -c "DROP DATABASE IF EXISTS storage_mgt;")
  end

  def create_database do
    System.cmd ~s(psql -U postgres -c "CREATE DATABASE storage_mgt;")
  end

  teardown do
    drop_database
  end

  test "storage up (twice in a row)" do
    assert Postgres.storage_up(correct_params) == :ok
    assert Postgres.storage_up(correct_params) == { :error, :already_up }
  end

  test "storage up (wrong credentials)" do
    refute Postgres.storage_up(wrong_user) == :ok
  end

  test "storage down (twice in a row)" do
    create_database

    assert Postgres.storage_down(correct_params) == :ok
    assert Postgres.storage_down(correct_params) == { :error, :already_down }
  end

  test "storage down (wrong credentials)" do
    create_database
    refute Postgres.storage_down(wrong_user) == :ok
  end
end
