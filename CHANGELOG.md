# Changelog

## v0.7.3-dev

* Enhancements
  * Allow changesets to be merged with `Ecto.Changeset.merge/2`
  * Add `Ecto.Changeset.put_new_change/3`
  * Support the `:using` option for indexes in Postgres
  * Support adding/dropping indexes concurrently with Postgres
  * Allow expressions to be given as default when adding columns via `fragment/1`
  * Support integer casting on float types
  * Explicitly checks if adapter supports ddl transactions
  * Log query parameters (this means custom log functions should now expect another element in the query tuple)

* Bug fixes
  * Only drop existing indexes when reversing `create index`
  * Allow boolean literals as defaults when adding columns
  * Add default varchar size to migrations

* Backwards incompatible changes
  * `uuid()` and `<<>>` syntax in queries has been removed in favor of explicit parameters

## v0.7.2 (2015-01-29)

* Enhancements
  * Support `Ecto.Query.exclude/2` that resets a previously set query field
  * Support more robust transactional tests via explicit `Ecto.Adapters.SQL.restart_test_transaction` command

* Bug fixes
  * Ensure `psql` does not require a database with the same name as the user

## v0.7.1 (2015-01-27)

* Enhancements
  * Support `after_load/2` and `after_load/3` callbacks
  * Support casting floats and integers in addition to string in `Decimal`
  * Add `__state__` field that to every schema that is either `:built`, `:loaded` or `:deleted`
  * Add `Ecto.Changeset.apply/1`
  * Support times with miliseconds when casting `Ecto.Time` and `Ecto.DateTime`

* Bug fixes
  * Do not accept default, null or primary key options in modify
  * Ensure `Ecto.Model.assoc/2` with `has_* :through` has the association as source in from
  * Properly implement `blank?` for `Ecto.UUID` and `Ecto.DateTime`
  * Ensure `psql` actually works on Windows and does not set locale data by default
  * Make options optional in `Ecto.Adapters.SQL.query/4`

## v0.7.0 (2015-01-25)

* Enhancements
  * Provide `Ecto.Adapters.SQL` with implementation to be shared by SQL adapters
  * Allow `disctinct: selector` in query syntax
  * Support `has_many :through` and `has_one :through` associations. `:through` can nest any type of association through n-levels
  * Provide `type/2` in query syntax for explicitly casting any external value
  * Add `Ecto.UUID` type that handles UUIDs as strings
  * Add casting support to `Ecto.DateTime` and related types
  * Allow a map with atom keys or a map with string keys in `Ecto.Changeset.cast/4`

* Bug fixes
  * Fix a limitation where only one nameless join could be given to a query
  * Ensure duplicated preloads are loaded only once
  * Ensure `p.field` in select returns the proper field type

* Backwards incompatible changes
  * `Ecto.Adapters.Postgres.query/4` has been renamed to `Ecto.Adapters.SQL.query/4`
  * `Ecto.Adapters.Postgres.begin_test_transaction/2` has been renamed to `Ecto.Adapters.SQL.begin_test_transaction/2`
  * `Ecto.Adapters.Postgres.rollback_test_transaction/2` has been renamed to `Ecto.Adapters.SQL.rollback_test_transaction/2`
  * Mix tasks now expect the repository with the option `-r`, otherwise it defaults to the application based one
  * `:datetime`, `:time` and `:date` will now return tuples in Ecto queries. To keep the previous behaviour, please replace the types in your schema with `Ecto.DateTime`, `Ecto.Time` and `Ecto.Date`
  * `Ecto.Changeset.validate_change/4` now passes the `field` and `value` to the callback function instead of only the `value`

## v0.6.0 (2015-01-17)

* Enhancements
  * Pass the repository with the changeset to callbacks
  * Add `template`, `encoding`, `lc_collate` and `lc_ctype` options to adapter that are used when creating the database
  * Add support for timestamps via the `timestamps/0` macro in schemas and `Ecto.Model.Timestamps`
  * Add `validate_unique/3` to `Ecto.Changeset`
  * Support setting `:auto_field` to false in `Ecto.Schema.belongs_to/3`
  * Add support for migrations (the previous migration style no longer works, just replace the SQL commands by `execute/1` calls). If you have ran migrations previously, you will have to add an inserted_at column with type `datetime/timestamp` to your `schema_migrations` table. This column can be added using the new migrations themselves.

* Bug fixes
  * Do not choke on empty `order_by` or `group_by` during query generation
  * Ensure queries are logged even during crashes

* Backwards incompatible changes
  * Previously deprecated validations have been removed
  * Previously deprecated repository configuration has been removed

## v0.5.1 (2015-01-13)

* Enhancements
  * Add `Ecto.Changeset.change/2`, `Ecto.Changeset.fetch_field/2` and `Ecto.Changeset.get_field/2`
  * Allow atoms and dynamic values in `order_by`

* Bug fixes
  * Ensure fields in `Ecto.Repo.update_all/3` are dumped before being sent to the database

## v0.5.0 (2015-01-12)

* Enhancements
  * Make `Ecto.Schema.schema/2` configuration uniform
  * Add `Ecto.Changeset` which is able to filter, cast and validate parameters for changes
  * Support custom types via the `Ecto.Type` behaviour
  * Support `read_after_writes` configuration for reading particular fields after we insert or update entries in the repository

* Bug fixes
  * Require interpolation operator in joins

* Deprecations
  * Validations are deprecated in favor of `Ecto.Changeset` validations
  * `def conf` in the repository is deprecated, instead pass the :otp_app option on `use Ecto.Repo` and define the repository configuration in the `config/config.exs` file. Some features like generators and migrations will be disable until you convert to the new configuration

* Backwards incompatible changes
  * `@schema_defaults` was removed in favor of setting `@primary_key` and `@foreign_key_type` directly
  * `Ecto.Schema.schema/2` options were removed in favor of setting `@primary_key` and `@foreign_key_type` before the `schema/2` call
  * `Ecto.Model.Schema` has been renamed to `Ecto.Schema`
  * `before_insert`, `after_insert`, `before_update` and `after_update` in `Ecto.Model.Callbacks` now receive changesets

## v0.4.0 (2015-01-02)

* Enhancements
  * Provide `Ecto.Model.build/2` and `Ecto.Model.assoc/2` for building and retrieving associations as queries. It is recommended to `import Ecto.Model` into your modules
  * Associations have been rewriten into a simpler and faster mechanism that does not require `.get`, `.all` and friends
  * Add `Repo.preload/2`
  * `Ecto.Query.preload/3` now supports query joins to be given
  * Allow dynamic values for join qualifiers and join tables
  * Define a behaviour named `Ecto.Associations` which defines the callback functions required to be implemented by associations

* Backwards incompatible changes
  * Association proxies have been removed. This means `post.comments` returns `Ecto.Associations.NotLoaded` until `post.comments` has been explicitly preloaded. However, once preloaded, the comments list can be accessed directly
  * Queryable implementation for associations has been removed. This means `Repo.all post.comments` no longer returns all comments. Instead use `Repo.all Ecto.Model.assoc(post, :comments)`. It is recommended to `import Ecto.Model` into your modules
  * `join: p.comments` has been removed in favor of `join: assoc(p, :comments)`
  * `assoc/2` in `select` is deprecated, please use `Ecto.Query.preload/3` instead
  * `Ecto.Associations.Preloader.preload/3` was removed in favor of `Repo.preload/2`

## v0.3.0 (2014-12-26)

* Enhancements
  * Support fragments in queries with the `fragment(...)` function
  * Interpolated values in queries are now automatically cast. For example, `from u in User, where: u.age > ^"10"` will automatically cast "10" to an integer. Failing to cast will trigger an `Ecto.CastError`
  * `preload`, `lock` and `order_by` now allow dynamic values
  * Improve and relax type inference. Ecto no longer requires `array(array, type)`, `binary(...)` and so on for interpolated values. In fact, the functions above have been removed

* Backwards incompatible changes
  * `:virtual` type no longer exists, instead pass `virtual: true` as field option
  * Adapter API for `insert`, `update` and `delete` has been simplified

## v0.2.8 (2014-12-16)

* Bug fixes
  * Validation predicates now receive the attribute as first argument

## v0.2.7 (2014-12-15)

* Enhancements
  * Add support for `Ecto.Model.Callbacks`

* Bug fixes
  * Fix merging of validation errors when using validation_also

## v0.2.6 (2014-12-13)

* Enhancements
  * Log queries by default
  * Pretty print queries (`Inspect` protocol implemented)

* Bug fixes
  * Cast primary key in `Repo.get/2`
  * Use repository port in Mix tasks
  * Fix type checking in `Repo.update_all/2`

* Backwards incompatible changes
  * Return validation errors as maps
  * Fix belongs_to preload if no associated record exists

## v0.2.5 (2014-09-17)

* Enhancements
  * Change timeout of migration queries to infinity
  * Add uuid type

* Bug fixes
  * Fix encoding of interpolated `nil` values
  * Support interpolated large integers
  * Support interpolating values on `Repo.update_all`
  * Correctly handle `nil` values inside `array/2` and `binary/1`

* Backwards incompatible changes
  * Do not translate `foo == nil` to the SQL `foo IS NULL`, provide `is_nil/1` instead

## v0.2.4 (2014-09-08)

* Enhancements
  * Better error message if repo is not started
  * Do not require `^` on literals inside `array/2` or `field/2`
  * Parametrize queries, interpolated values are no longer encoded as literals in the generated SQL query, instead they are sent as query parameters
  * Allow starting the `assoc` selection from a joined association or building it from *right* outer joins

* Bug fixes
  * Remove possible deadlock for models using each other in queries

## v0.2.3 (2014-08-03)

* Enhancements
  * Add `local` and `utc` to `Ecto.DateTime` and `Ecto.Date`

* Bug fixes
  * Treat `nil` as an any data type
  * Support array of binaries
  * Avoid race conditions when optimizing query compilation

## v0.2.2 (2014-06-30)

* Enhancements
  * Do not require username and password to be present in `parse_url/1`

## v0.2.1 (2014-06-18)

* Enhancements
  * Add support for all query expressions in `order_by`, `group_by` and `distinct` expressions, instead of only allowing lists of fields
  * Add `Ecto.Model.scoped/2` as a shorthand for `from(x in __MODULE__, ...)`

* Bug fixes
  * Aggregate functions in `order_by`, `distinct` and `select` will make the query grouped

* Backwards incompatible changes
  * Single variables in `group_by` and `distinct` no longer expands to a list of fields

## v0.2.0 (2014-05-24)

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

## v0.1.0 (2014-05-01)

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

## v0.0.1

* Initial release
