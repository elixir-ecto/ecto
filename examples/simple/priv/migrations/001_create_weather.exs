defmodule Repo.CreatePosts do
  use Ecto.Migration

  def up do
    """
    CREATE TABLE weather (
    id        SERIAL,
    city      varchar(40),
    temp_lo   integer,
    temp_hi   integer,
    prcp      float
    )
    """
  end

  def down do
    "DROP TABLE weather"
  end
end
