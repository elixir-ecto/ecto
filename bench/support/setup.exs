Code.require_file("repo.exs", __DIR__)
Code.require_file("migrations.exs", __DIR__)
Code.require_file("models.exs", __DIR__)

alias Ecto.Bench.{PgRepo, MySQLRepo, CreateUser}

{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(PgRepo.config(), :temporary)
{:ok, _} = Ecto.Adapters.MySQL.ensure_all_started(MySQLRepo.config(), :temporary)

_ = Ecto.Adapters.Postgres.storage_down(PgRepo.config())
:ok = Ecto.Adapters.Postgres.storage_up(PgRepo.config())

_ = Ecto.Adapters.MySQL.storage_down(MySQLRepo.config())
:ok = Ecto.Adapters.MySQL.storage_up(MySQLRepo.config())

{:ok, _pid} = PgRepo.start_link(log: false)
{:ok, _pid} = MySQLRepo.start_link(log: false)

:ok = Ecto.Migrator.up(PgRepo, 0, CreateUser, log: false)
:ok = Ecto.Migrator.up(MySQLRepo, 0, CreateUser, log: false)
