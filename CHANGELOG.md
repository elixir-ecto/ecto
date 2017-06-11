# Changelog for v2.2

## Highlights

## v2.2.0-dev

### Enhancements

  * [Ecto.Adapters.Postgres] Use the "postgres" database for create/drop database commands
  * [Ecto.Adapters.MySQL] Use Mariaex instead of MySQL client to create & drop database
  * [Ecto.Changeset] Add `apply_action/2`
  * [Ecto.Migrations] Add reversible `execute/2` to migrations
  * [Ecto.Migrations] Add SQL views support
  * [Ecto.Migrator] Allow migration/rollback to log SQL commands via the `--log-sql` flag
  * [Ecto.LogEntry] Add `:caller_pid` to the Ecto.LogEntry struct
  * [Ecto.Repo] Implement `:returning` option on insert
  * [Ecto.UUID] Allow casting binary UUIDs
  * [mix ecto.drop] Add `--force`

### Bug fixes

  * [Ecto.Query] Properly expand macros in `select`

### Deprecations

  * [Ecto.DateTime] `Ecto.DateTime` as well as `Ecto.Date` and `Ecto.Time` are deprecated in favor of `:naive_datetime`, `:date` and `:time` respectively
  * [Ecto.Repo] Using `{:system, env}` to configure the repository URL is deprecated in favor of a custom init/2 callback

## Previous versions

  * See the CHANGELOG.md [in the v2.1 branch](https://github.com/elixir-ecto/ecto/blob/v2.1/CHANGELOG.md)
