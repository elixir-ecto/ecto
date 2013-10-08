defmodule MyApp.MyMigration do
  
  use Ecto.Migration

  def up do
    "CREATE TABLE IF NOT EXISTS products(id serial primary key, price integer);"
  end

  def down do
    "DROP TABLE user;"
  end
end