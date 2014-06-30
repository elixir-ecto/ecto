# v0.2.2 (2014-06-30)

* Enhancements
  * Do not require username and password to present in `parse_url/1`

# v0.2.1 (2014-06-18)

* Enhancements
  * Add support for all query expressions in `order_by`, `group_by` and `distinct` expressions, instead of only allowing lists of fields
  * Add `Ecto.Model.scoped/2` as a shorthand for `from(x in __MODULE__, ...)`

* Bug fixes
  * Aggregate functions in `order_by`, `distinct` and `select` will make the query grouped

* Backwards incompatible changes
  * Single variables in `group_by` and `distinct` no longer expands to a list of fields

# v0.2.0 (2014-05-24)

* Enhancements
  * Add `Ecto.Assocations.load/3` for loading associations
  * Add `Ecto.Model.primary_key/1` and `Ecto.Model.put_primary_key/3` for accessing a model's primary key
  * Add `Ecto.Repo.one` and `Ecto.Repo.one!` for running query expecting one result
  * Add `Ecto.Repo.get!` that raises when receiving no result
  * Set foreign key when loading belongs_to association to model

* Bug fixes
  * Ensure that existing primary key is not overwritten when inserting model
  * `Ecto.Repo.get` no longer adds `limit: 1` to query, it will now raise when receiving more than one result
  * Properly underscore camelized names in associated models

* Backwards incompatible changes
  * Removed entities in favor of schema + structs. In particular, `Ecto.Entity` is gone as well as the `queryable/2` macro. Instead developers should invoke `schema/2` in their models, which will automatically define a struct in the current module. Now to create or update, developers should use `struct(Post, [])` or `%Post{}` instead of the previous `Post.new([])` or `Post[]`
  * Renamed has_many association function `to_list` to `all`
  * `Ecto.Repo.storage_down` and `Ecto.Repo.storage_up` moved to `Ecto.Storage`

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
