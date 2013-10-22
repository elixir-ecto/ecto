defmodule MyApp.MyMigration do
  use Ecto.Migration

  def up do
    "CREATE TABLE products(id serial primary key, price integer);"
  end

  def down do
    "DROP TABLE products;"
  end
end
