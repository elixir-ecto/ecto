# v0.1.0-dev

* Enhancements
  * Add `ecto.migrate` and `ecto.rollback` tasks, support `--to`, `--step` and `--all`
  * Do not require Ecto URI schema to start with `ecto`
  * Allow `:on` with association joins on keywords syntax
  * Add Decimal support

* Bug fixes

* Deprecations

* Backwards incompatible changes
  * `Ecto.Binary[]` is no longer used to wrap binary values. Instead always use `binary/1` in queries
  * `:list` type changed name to `:array`. Need to specify inner type for arrays in entity fields
  * Literal lists no longer supported in queries. Need to specify inner type; use `array(list, ^:integer)` instead

# v0.0.1

* Initial release
