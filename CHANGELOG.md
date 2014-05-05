# v0.2.0-dev

* Backwards incompatible changes
  * Removed entities in favor of schema + structs. In particular, `Ecto.Entity` is gone as well as the `queryable/2` macro. Instead developers should invoke `schema/2` in their models, which will automatically define a struct in the current module. Now to create or update, developers should use `struct(Post, [])` or `%Post{}` instead of the previous `Post.new([])` or `Post[]`

# v0.1.0 (2014-05-01)

* Enhancements
  * Add `ecto.migrate` and `ecto.rollback` tasks, support `--to`, `--step` and `--all`
  * Do not require Ecto URI schema to start with `ecto`
  * Allow `:on` with association joins on keywords syntax
  * Add Decimal support
  * Add 'distinct' query expression
  * Add `Validator.bin_dict/2`
  * Add `Ecto.Repo.rollback` for explicit transaction rollback
  * Add support for timeouts on Repo calls
  * Add `:date` and `:time` types

* Bug fixes
  * Fix association functions resetting the entity when manually loading associated entities
  * Fix a bug where an association join's 'on' expression didn't use the bindings
  * `Enum.count/1` on has_many associations shouldn't break

* Deprecations
  * Rename `Repo.create/1` to `Repo.insert/1`

* Backwards incompatible changes
  * `Ecto.Binary[]` is no longer used to wrap binary values. Instead always use `binary/1` in queries
  * `:list` type changed name to `:array`. Need to specify inner type for arrays in entity fields
  * Literal lists no longer supported in queries. Need to specify inner type; use `array(list, ^:integer)` instead
  * Remove `url/0` for configuration of repos in favor of `conf/0` in conjunction with `parse_url/1`
  * Query functions `date_add/1` and `date_sub/1` renamed to `time_add/1` and `time_sub/1` respectively, they also accept the types `:time` and `:date`

# v0.0.1

* Initial release
