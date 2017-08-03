# Changelog for v2.2

## Highlights

## v2.2.0-dev

### Enhancements

  * [Ecto.Adapters.Postgres] Use the "postgres" database for create/drop database commands
  * [Ecto.Adapters.MySQL] Use Mariaex instead of MySQL client to create & drop database
  * [Ecto.Changeset] Add `apply_action/2`
  * [Ecto.Changeset] Add prefix constraint name checking to constraint validations
  * [Ecto.Migrations] Add reversible `execute/2` to migrations
  * [Ecto.Migrator] Allow migration/rollback to log SQL commands via the `--log-sql` flag
  * [Ecto.LogEntry] Add `:caller_pid` to the Ecto.LogEntry struct
  * [Ecto.Query] Allow map updates in subqueries
  * [Ecto.Repo] Implement `:returning` option on insert
  * [Ecto.Repo] Set struct prefix on `insert`, `delete`, and `update` when the prefix is given as an option
  * [Ecto.Schema] Validate schemas after compilation - this helps developers catch early mistakes such as foreign key mismatches early on
  * [Ecto.UUID] Allow casting binary UUIDs
  * [mix ecto.drop] Add `--force`
  * [mix ecto.load] Add `--force` and prompt user to confirm before continuing in production

### Bug fixes

  * [Ecto.Changeset] Remove the field from changes if it does not pass validate_required
  * [Ecto.Query] Properly expand macros in `select`
  * [Ecto.Query] Support `or_having` in keyword query
  * [Ecto.UUID] Validate UUID version on casting

### Deprecations

  * [Ecto.DateTime] `Ecto.DateTime` as well as `Ecto.Date` and `Ecto.Time` are deprecated in favor of `:naive_datetime`, `:date` and `:time` respectively
  * [Ecto.Repo] Using `{:system, env}` to configure the repository URL is deprecated in favor of a custom init/2 callback

## Previous versions

  * See the CHANGELOG.md [in the v2.1 branch](https://github.com/elixir-ecto/ecto/blob/v2.1/CHANGELOG.md)
