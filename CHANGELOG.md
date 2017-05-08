# Changelog for v2.2

## Highlights

## v2.2.0-dev

### Enhancements

  * [Ecto.Adapters.Postgres] Use the "postgres" database for create/drop database commands
  * [Ecto.Adapters.MySQL] Use Mariaex instead of MySQL client to create & drop database
  * [Ecto.Changeset] Add `apply_action/2`
  * [Ecto.Migrator] Allow migration/rollback to log SQL commands via the `--log-sql` flag
  * [Ecto.Repo] Implement `:returning` option on insert
  * [mix ecto.drop] Add `--force`

### Bug fixes

  * [Ecto.Query] Properly expand macros in `select`

### Deprecations

## Previous versions

  * See the CHANGELOG.md [in the v2.1 branch](https://github.com/elixir-ecto/ecto/blob/v2.1/CHANGELOG.md)
