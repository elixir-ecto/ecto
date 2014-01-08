# v0.1.0-dev

* Enhancements
  * Add `ecto.migrate` and `ecto.rollback` tasks, support `--to`, `--step` and `--all`
  * Do not require Ecto URI schema to start with `ecto`
  * Allow `:on` with association joins on keywords syntax

* Bug fixes

* Deprecations

* Backwards incompatible changes
  * `Ecto.Binary[]` is no longer used to wrap binary values. Instead always use `binary/1` in queries

# v0.0.1

* Initial release
