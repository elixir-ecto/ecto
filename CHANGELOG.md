# Changelog

## v1.0.1

* Bug fixes
  * Raise a proper error message if trying to change a belongs_to association
  * Raise a proper error message if Ecto.Model/Ecto.Schema are used but no schema is defined
  * Ensure dump after cast is still handled as `Ecto.CastError` as it assumes poor casting
  * Support constraints on Postgres versions earlier than 9.4

## v1.0.0

* Enhancements
  * Support fragment sources in join
  * Also lookup in the changes map for required fields when casting changesets
  * ALlow table and index commands in migration to be pipeable

* Bug fixes
  * Ensure constraints errors when saving nested association returns the parent changed and not the child one
  * Ensure rollback only closes innermost transaction
  * Ensure the user changeset containing embeds and assocs is returned when there is a constraint error
  * Ensure binary_ids models can specify `unique_constraint` for SQL databases

## v0.16.0

* Enhancements
  * Add functionality for constraint checking in the storage to `Ecto.Changeset`. Support was added for `unique_constraint/3` (powered by unique indexes) and `foreign_key_constraint/3`, `assoc_constraint/3` (belongs to) and `no_assoc_constraint/3` (has one/many)
  * Support empty lists as default values
  * Support changing/setting null and default on `modify/3` in migrations

* Bug fixes
  * Do not generate changes when parameters are `:empty` even for embeds/associations
  * Raise on bad options in `validate_number/3`
  * `get_field/3` and `fetch_field/2` for relations return models
  * Ensure NULL and DEFAULT are respected when defining references

* Deprecations
  * `Ecto.Changeset.validate_unique/3` is deprecate in favor of `Ecto.Changeset.unique_constraint/3`. Read the documentation for the latter for more information on updating

* Backwards incompatible changes
  * `Ecto.Adapters.SQL.query/4` now returns `{:ok, result}`. Use `Ecto.Adapters.SQL.query!/4` for the previous behaviour

* Adapter backwards incompatible changes
  * Receive context on `Ecto.Adapter.insert/update/delete`. Expect context on schema load.

## v0.15.0

* Enhancements
  * Add query generation caching
  * Add `compare/2` to `Ecto.DateTime` and friends
  * Add `Ecto.Query.API` with the purpose of documenting query functions
  * Add `Ecto.Migration.rename/3` to rename columns
  * Support changing `has_one` and `has_many` via changesets

* Deprecations
  * `:size` option in adapter configuration has been renamed to the more obvious `:pool_size`

* Backwards incompatible change
  * `exists?/1` helper in migration has been removed in favor of `create_if_not_exists` and `drop_if_exists`
  * `rename table(:foo), table(:bar)` in migrations has been changed to `rename table(:foo), to: table(:bar)`
  * `Ecto.NoPrimaryKeyError` was renamed to `Ecto.NoPrimaryKeyFieldError`
  * `Ecto.MissingPrimaryKeyError` was renamed to `Ecto.NoPrimaryKeyValueError`

## v0.14.3

* Enhancements
  * Add `Ecto.Schema.embedded_schema/0`

* Bug fixes
  * Multiple bug fixes when working with embeds

## v0.14.2

* Bug fixes
  * Fix an error where using `type/2` in queries was not offsetting parameters properly
  * Do not allow casting of embeds in queries
  * Do not store embed as change if it is on update, it is valid and its changeset has no changes
  * Make sure :any type works correctly with custom types on `Ecto.Type.match?/2`

## V0.14.1

* Bug fixes
  * Also tag action in changeset when changeset is invalid

## v0.14.0

* Experimental features (please try them out and give feedback)
  * Add `Ecto.Pools.SojournBroker` as a more flexible and customizable alternative to `Ecto.Pools.Poolboy`
  * Support for `embeds_one` and `embeds_many`

* Enhancements
  * Add `Ecto.Adapters.SQL.to_sql/3`
  * Allow preloads to be customized with queries
  * Store the connection PID in `Ecto.LogEntry`
  * Support `:on_delete` when defining `has_many` and `belongs_to` in schema
  * Allow renaming tables in migration
  * Include Ecto's processing time along side adapter processing on `Ecto.LogEntry.query_time`
  * Introduce `Ecto.Repo.after_connect/1`
  * Support `date_add/3` and `datetime_add/3` for interval based datetime operations
  * Support `:push` and `:pull` array operations in `Ecto.Repo.update_all/3`

* Bug fixes
  * Ensure uniqueness validatior runs the proper check when a scope changed but the value is still the same
  * Fix a bug where it was not possible to add a references column in MySQL in an alter table
  * Minimize query rewriting in has_many/one :through, ensuring a wilder variety of associations are supported
  * Do not fail when compiling queries with empty order or group by expressions
  * Ensure literals in queries are also cast/dump
  * `Ecto.Adapters.SQL.query/4` now returns a list of lists instead of a list of tuples

* Backwards incompatible changes
  * `Ecto.Repo.update!/2` no longer invokes callbacks if there were no changes, avoiding writing to the database at all (use `:force` to force callback execution)
  * `Ecto.Repo.transaction/2` is now flattened. This means that multiple transaction calls will no longer use savepoints, instead it will be considered as a single transaction, where a failure in any transaction block will trigger the outmost transaction to rollback, even if failures are rescued. This should only affect users that were explicitly relying on the savepoints.
  * `:date`, `:time` and `:datetime` were removed in favor of `Ecto.Date`, `Ecto.Time` and `Ecto.DateTime`
  * `Ecto.Changeset.errors` now return `{"must be less than %{count}", count: 3}` instead of `{"must be less than %{count}", 3}`

* Adapter backwards incompatible changes
  * Pass `{source, model}` in `Ecto.Adapter.insert/update/delete`
  * SQL adapters are not expected to return each row as a list instead of a tuple
  * `id_types/0` were removed in favor of `load/2` and `dump/2`

## v0.13.1

* Bug fixes
  * Allow `Ecto.Adapters.SQL.Sandbox` to start lazily
  * Fix race conditions in case of crashes in new sandbox pool

## v0.13.0

* Enhancements
  * Support a `:map` type. PostgreSQL will use `jsonb` columns for those while other SQL databases will emulate it with a text column until JSON support is added
  * Add keyword query fragments: `fragment("$set": [foo: "bar"])`. This will be useful to databases which cannot express their queries as strings
  * Allow type tagging with field name: `select: type(^some_value, p.uuid)`
  * Support checking if a value exists in an array: `where: "ecto" in p.tags`
  * Allow custom options to be given when creating a table: `create table(:posts, options: "WITH ...")`
  * Support `:on_delete` in `Ecto.Migration.references/2`. It may be one of `:nothing`, `:delete_all` or `:nilify_all`. Defaults to `:nothing`.
  * Add `Ecto.Adapter.Pool` which will support adpaters to work with different pools (upcoming)
  * Add `Ecto.Changeset.validate_subset/4` to validate a list is a subset of the given values
  * Support encoded URLs in the repository configuration

* Backwards incompatible changes
  * `Ecto.Adapters.SQL` now requires using `Ecto.Adapters.SQL.Sandbox` for transactional tests. You will have to update your adapter tests to use `pool: Ecto.Adapters.SQL.Sandbox`.
  * `Ecto.Repo.update_all/3` and `Ecto.Repo.delete_all/3` now return `{counter, nil}` instead of simply `counter`. This is done to support RETURNING statements in the future.
  * `Ecto.Repo.update_all/3` is no longer a macro. Instead of:

        Repo.update_all queryable, foo: "bar"

    One should write:

        Repo.update_all queryable, set: [foo: "bar"]

    Where `:set` is the update operator. `:inc` is also
    supported to increment a given column by the given value:

        Repo.update_all queryable, inc: [foo: 1]

    For complex expressions, updates are now also supported in
    queries:

        query = from queryable, update: [set: [foo: p.bar]]
        Repo.update_all query, []

## v0.12.1

* Bug fix
  * Improvements related to adapter compatibility

## v0.12.0

Release notes at: https://github.com/elixir-lang/ecto/releases/tag/v0.12.0

* Enhancements
  * Add `put_source/2` function to `Ecto.Model`
  * Allow binary literal syntax in queries
  * Optimize SQL transactions by reducing the amount of messages passed around
  * Provide `Ecto.Adapters.Worker` which can work across adapters and provides transactional semantics
  * Support `:autogenerate` for custom types
  * Introduce new `:id` and `:binary_id` types that support autogeneration inside primary keys and are handled by the database

* Bug fixes
  * Ensure confirmation is required if field is given but nil

* Deprecations
  * `:read_after_writes` is deprecated in favor of `:autogenerate` in `Ecto.Schema.field/3`
  * `Repo.insert/2` is deprecated in favor of `Repo.insert!/2`
  * `Repo.update/2` is deprecated in favor of `Repo.update!/2`
  * `Repo.delete/2` is deprecated in favor of `Repo.delete!/2`

* Backwards incompatible changes
  * `Repo.log/2` is no longer invoked. Instead `Repo.log/1` is called with an `Ecto.LogEntry`
  * `:auto_field` in `belongs_to/3` has been renamed to `:define_field`
  * `:uuid` type has been removed in favor of `Ecto.UUID`

* Adapters backwards incompatible changes
  * fragment AST now tags each argument as raw or expr
  * `Ecto.Adapter.insert` now receives an extra argument telling which key to autogenerate. The value may be: `{field :: atom, type :: :id | :binary_id, value :: term | nil} | nil`. If `nil`, there is no key to autogenerate. If a tuple, it may have type `:id` or `:binary_id` with semantics to be specified by the adapter/database. Finally, if the value is `nil`, it means no value was supplied by the user and the database MUST return a new one.

## v0.11.3 (2015-05-19)

* Enhancements
  * Add `validate_confirmation/3`
  * Normalize ports for MySQL and PostgreSQL

* Bug fixes
  * Ensure changes in changesets can be reset to their original value

## v0.11.2 (2015-05-06)

* Bug fixes
  * Trigger `validate_unique/3` if the field or any of the scopes changed
  * Do not trigger `validate_unique/3` if the field or scopes contains errors
  * Ensure repo log calls can be optimized out
  * Improve error message when model types are given on migrations

## v0.11.1 (2015-05-05)

* Enhancements
  * Add `force_change/3` to force a change into a changeset

* Bug fixes
  * `put_change/3` and `change/2` in `Ecto.Changeset` also verify the model value before storing the change

## v0.11.0 (2015-05-04)

* Enhancements
  * Add `Ecto.Repo.get_by/3` and `Ecto.Repo.get_by!/3`
  * Add `to_erl`/`from_erl` to datetime modules
  * Add `:scope` option to `Ecto.Changeset.validate_unique/2`
  * Allow `distinct(query, true)` query expression
  * Effectively track dirty changes in `Ecto.Changeset`. If the value being sent as parameter is the same as the value in the model, it won't be sent to the Repo on insert/update

* Deprecations
  * Deprecate `nil` as parameters in `Ecto.Changeset.cast/4` in favor of `:empty`

* Backwards incompatible changes
  * The pool size now defaults to 10 with no overflow. This will affect you if you were not explicitly setting those values in your pool configuration.
  * `Ecto.Model` now only imports `from/2` from `Ecto.Query` out of the box
  * `Ecto.Changeset.apply/1` was removed in favor of `Ecto.Changeset.apply_changes/1`

## v0.10.3 (2015-05-01)

* Enhancements
  * Relax poolboy dependency

## v0.10.2 (2015-04-10)

* Enhancements
  * Add `Ecto.DateTime.from_date/1`
  * Allow adapter to be configured at the `:repo` level
  * Add `--quiet` to `ecto.migrate`, `ecto.create` and `ecto.drop` tasks
  * Support `timestampz` type for PostgreSQL

* Bug fixes
  * Ensure `:invalid` error shows up as "is invalid" message
  * Improve support for "schema.table" queries in MySQL and PostgreSQL

## v0.10.1 (2015-03-25)

* Enhancements
  * Add an option to set the engine when creating a table (used by MySQL and defaults to InnoDB). This ensures Ecto works out of the box with earlier MySQL versions

* Bug fixes
  * No longer create database in `ecto.migrate` if one does not exist
  * Fix a bug where dates earlier than 2000 could not be saved in Postgres

## v0.10.0 (2015-03-21)

* Enhancements
  * Add `validate_number/3` to `Ecto.Changeset`
  * Add cardinality to `Ecto.Association.NotLoaded`
  * Allow `{"source", Model}` as a source in queries and associations
  * Add support for usec in `Ecto.Date`, `Ecto.Time` and `Ecto.DateTime`
  * Add `usec: true` support to `Ecto.Schema.timestamps/1`
  * Create database in `ecto.migrate` if one does not exist
  * `Repo.preload/2` no longer preloads already loaded associations

* Backwards incompatible changes
  * Using `distict: EXPR` automatically sets the given distinct expressions in `order_by`
  * `__state__` field has been removed in favor of a `__meta__` field which includes the state and the model source
  * Error messages in `Ecto.Changeset` now return strings instead of atoms
  * `Ecto.Model.primary_key/1` now returns a keyword list of primary key fields, returning an empty list when there is no primary key. Use `Ecto.Model.primary_key!/1` for the raising variant
  * Use simple representations when converting `Ecto.Date`, `Ecto.Time` and `Ecto.DateTime` to strings. Use `to_iso8601` for the ISO specific formatting
  * `@timestamps_type Your.Type` was removed in favor of `@timestamps_opts [type: Your.Type]`

## v0.9.0 (2015-03-05)

* Enhancements
  * Add MySQL support
  * Log when migration is already up/down
  * Add `Ecto.Association.loaded?/1`
  * Support joins besides where clauses in `update_all` and `delete_all`
  * Support optimistic locking with `Ecto.Model.OptimisticLock`
  * Allow timeout when querying the database to be configured via `:timeout`
  * Allow timeout when connecting to the database to be configured via `:connect_timeout`
  * Support maps in select in queries
  * Allow custom macros to be used in queries
  * Support `distinct: true` that simply sets SELECT DISTINCT

* Backwards incompatible changes
  * Primary keys are no longer automatically marked with `read_after_writes`. If you have a custom primary key that is AUTO INCREMENT/SERIAL in the database, you will have to pass `read_after_writes: true` as option when setting `@primary_key`
  * Remove blank checks from `Ecto.Changeset.cast/4` (you should automatically set the parameters values to nil before calling `cast/4`. If you are using Phoenix, Phoenix master has a `plug :scrub_params, "user"` for that)
  * `Ecto.Changeset.cast/4` now expects the changeset/model as first argument and the parameters as second
  * `Ecto.Query.distinct/3` can now be specified on queries just once
  * `Ecto.Associations` renamed to `Ecto.Association` (unlikely to affect user code)

* Deprecations
  * The `:adapter` option should now be specified in the config file rather than when using `Ecto.Repo` (you will receive a warning if you don't)

* Adapter API changes
  * `:time` types now use a tuple of four elements (hour, min, sec and msec)
  * `Ecto.Adapter.update/6` now expects the fields as third argument and filters as fourth
  * `Ecto.Migration.Reference` now have a default type of `:serial` that needs to be translated to the underlying primary key representation
  * `Ecto.Query` now has a `distinct` field (instead of `distincts`) and its expression may true, false or a list

## v0.8.1 (2015-02-13)

* Bug fixes
  * Ensure `in/2` queries on uuid/binary columns work

## v0.8.0 (2015-02-12)

* Enhancements
  * Allow changesets to be merged with `Ecto.Changeset.merge/2`
  * Support the `:using` option for indexes in Postgres
  * Support adding/dropping indexes concurrently with Postgres
  * Allow expressions to be given as default when adding columns via `fragment/1`
  * Support integer casting on float types
  * Explicitly checks if adapter supports ddl transactions
  * Log query parameters (this means custom log functions should now expect another element in the query tuple)

* Bug fixes
  * Only drop existing indexes when reversing `create index`
  * Allow boolean literals as defaults when adding columns
  * Add default size to migrations for string columns

* Backwards incompatible changes
  * `uuid()` and `<<>>` syntax in queries has been removed in favor of explicit parameters
  * `lock` expressions now must be a literal string

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
  * Define a behaviour named `Ecto.Association` which defines the callback functions required to be implemented by associations

* Backwards incompatible changes
  * Association proxies have been removed. This means `post.comments` returns `Ecto.Association.NotLoaded` until `post.comments` has been explicitly preloaded. However, once preloaded, the comments list can be accessed directly
  * Queryable implementation for associations has been removed. This means `Repo.all post.comments` no longer returns all comments. Instead use `Repo.all Ecto.Model.assoc(post, :comments)`. It is recommended to `import Ecto.Model` into your modules
  * `join: p.comments` has been removed in favor of `join: assoc(p, :comments)`
  * `assoc/2` in `select` is deprecated, please use `Ecto.Query.preload/3` instead
  * `Ecto.Association.Preloader.preload/3` was removed in favor of `Repo.preload/2`

## v0.3.0 (2014-12-26)

* Enhancements
  * Support fragments in queries with the `fragment(...)` function
  * Interpolated values in queries are now automatically cast. For example, `from u in User, where: u.age > ^"10"` will automatically cast "10" to an integer. Failing to cast will trigger an `Ecto.CastError`
  * `preload`, `lock` and `order_by` now allow dynamic values
  * Improve and relax type inference. Ecto no longer requires `array(array, type)`, `binary(...)` and so on for interpolated values. In fact, the functions above have been removed

* Backwards incompatible changes
  * `order_by` no longer accepts a negative value.  use `asc` or `desc` instead.  Eg.: `order_by: [asc: t.position]`
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
