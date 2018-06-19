Code.require_file("repo.exs", __DIR__)
Code.require_file("migration.exs", __DIR__)

alias Ecto.Bench.{PgRepo, MySQLRepo, Migration}

{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(PgRepo, :temporary)
{:ok, _} = Ecto.Adapters.MySQL.ensure_all_started(MySQLRepo, :temporary)

_ = Ecto.Adapters.Postgres.storage_down(PgRepo.config())
:ok = Ecto.Adapters.Postgres.storage_up(PgRepo.config())

_ = Ecto.Adapters.MySQL.storage_down(MySQLRepo.config())
:ok = Ecto.Adapters.MySQL.storage_up(MySQLRepo.config())

{:ok, _pid} = PgRepo.start_link()
{:ok, _pid} = MySQLRepo.start_link()

:ok = Ecto.Migrator.up(PgRepo, 0, Migration, log: false)
:ok = Ecto.Migrator.up(MySQLRepo, 0, Migration, log: false)
