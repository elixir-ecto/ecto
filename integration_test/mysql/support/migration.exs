defmodule Ecto.Integration.MySQL.Migration do
  use Ecto.Migration

  def change do
    execute("""
      create table `mysql_raw_on_non_pk` (
        `id` int(11) not null,
        `non_pk_auto_increment_id` int(11) NOT NULL AUTO_INCREMENT,
        PRIMARY KEY (`id`),
        UNIQUE KEY `mysql_raw_on_non_pk_index` (`non_pk_auto_increment_id`)
      );
    """)
  end
end
