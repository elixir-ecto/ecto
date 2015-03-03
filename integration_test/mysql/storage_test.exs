defmodule Ecto.Integration.StorageTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.MySQL

  def correct_params do
    [database: "storage_mgt",
     username: "root",
     password: nil,
     hostname: "localhost"]
  end

  def wrong_user do
    [database: "storage_mgt",
     username: "randomuser",
     password: "password1234",
     hostname: "localhost"]
  end

  def drop_database do
    :os.cmd 'mysql -u root -e "DROP DATABASE IF EXISTS storage_mgt;"'
  end

  def create_database do
    :os.cmd 'mysql -u root -e "CREATE DATABASE storage_mgt;"'
  end

  setup do
    on_exit fn -> drop_database end
    :ok
  end

  test "storage up (twice in a row)" do
    assert MySQL.storage_up(correct_params) == :ok
    assert MySQL.storage_up(correct_params) == {:error, :already_up}
  end

  test "storage up (wrong credentials)" do
    refute MySQL.storage_up(wrong_user) == :ok
  end

  test "storage down (twice in a row)" do
    create_database

    assert MySQL.storage_down(correct_params) == :ok
    assert MySQL.storage_down(correct_params) == {:error, :already_down}
  end

  test "storage down (wrong credentials)" do
    create_database
    refute MySQL.storage_down(wrong_user) == :ok
  end
end
