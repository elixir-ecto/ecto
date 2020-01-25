# Changelog for v3.x

## v3.3.2-dev

### Enhancements

  * [Ecto.Schema] Support `:join_through` on `many_to_many` associations

### Bug fixes

  * [Ecto.Schema] Respect child schema prefix in `cast_assoc`
  * [Ecto.Repo] Ignore empty hostname when parsing database url (Elixir v1.10 support)
  * [mix ecto.gen.repo] Use `config_path` when writing new config in ecto.gen.repo

## v3.3.1 (2019-12-27)

### Enhancements

  * [Ecto.Query.WindowAPI] Support `filter/2`

### Bug fixes

  * [Ecto.Query.API] Fix `coalesce/2` usage with mixed types

## v3.3.0 (2019-12-11)

### Enhancements

  * [Ecto.Adapter] Add `storage_status/1` callback to `Ecto.Adapters.Storage` behaviour
  * [Ecto.Changeset] Add `Ecto.Changeset.apply_action!/2`
  * [Ecto.Changeset] Remove actions restriction in `Ecto.Changeset.apply_action/2`
  * [Ecto.Repo] Introduce `c:Ecto.Repo.aggregate/2`
  * [Ecto.Repo] Support `{:replace_all_except, fields}` in `:on_conflict`

### Bug fixes

  * [Ecto.Query] Make sure the `:prefix` option in `:from`/`:join` also cascades to subqueries
  * [Ecto.Query] Make sure the `:prefix` option in `:join` also cascades to queries
  * [Ecto.Query] Use database returned values for literals. Previous Ecto versions knew literals from queries should not be discarded for combinations but, even if they were not discarded, we would ignore the values returned by the database
  * [Ecto.Repo] Do not wrap schema operations in a transaction if already inside a transaction. We have also removed the **private** option called `:skip_transaction`

### Deprecations

  * [Ecto.Repo] `:replace_all_except_primary_keys` is deprecated in favor of `{:replace_all_except, fields}` in `:on_conflict`

## v3.2.5 (2019-11-03)

### Bug fixes

  * [Ecto.Query] Fix a bug where executing some queries would leak the `{:maybe, ...}` type

## v3.2.4 (2019-11-02)

### Bug fixes

  * [Ecto.Query] Improve error message on invalid join binding
  * [Ecto.Query] Make sure the `:prefix` option in `:join` also applies to through associations
  * [Ecto.Query] Invoke custom type when loading aggregations from the database (but fallback to database value if it can't be cast)
  * [mix ecto.gen.repo] Support Elixir v1.9 style configs

## v3.2.3 (2019-10-17)

### Bug fixes

  * [Ecto.Changeset] Do not convert enums given to `validate_inclusion` to a list

### Enhancements

  * [Ecto.Changeset] Improve error message on non-atom keys to change/put_change
  * [Ecto.Changeset] Allow :with to be given as a `{module, function, args}` tuple on `cast_association/cast_embed`
  * [Ecto.Changeset] Add `fetch_change!/2` and `fetch_field!/2`

## v3.2.2 (2019-10-01)

### Bug fixes

  * [Ecto.Query] Fix keyword arguments given to `:on` when a bind is not given to join
  * [Ecto.Repo] Make sure a preload given to an already preloaded has_many :through is loaded

## v3.2.1 (2019-09-17)

### Enhancements

  * [Ecto.Changeset] Add rollover logic for default incremeter in `optimistic_lock`
  * [Ecto.Query] Also expand macros when used inside `type/2`

### Bug fixes

  * [Ecto.Query] Ensure queries with non-cacheable queries in CTEs/combinations are also not-cacheable

## v3.2.0 (2019-09-07)

v3.2 requires Elixir v1.6+.

### Enhancements

  * [Ecto.Query] Add common table expressions support `with_cte/3` and `recursive_ctes/2`
  * [Ecto.Query] Allow `dynamic/3` to be used in `order_by`, `distinct`, `group_by`, as well as in `partition_by`, `order_by`, and `frame` inside `windows`
  * [Ecto.Query] Allow filters in `type/2` expressions
  * [Ecto.Repo] Merge options given to the repository into the changeset `repo_opts` and assign it back to make it available down the chain
  * [Ecto.Repo] Add `prepare_query/3` callback that is invoked before query operations
  * [Ecto.Repo] Support `:returning` option in `Ecto.Repo.update/2`
  * [Ecto.Repo] Support passing a one arity function to `Ecto.Repo.transaction/2`, where the argument is the current repo
  * [Ecto.Type] Add a new `embed_as/1` callback to `Ecto.Type` that allows adapters to control embedding behaviour
  * [Ecto.Type] Add `use Ecto.Type` for convenience that implements the new required callbacks

### Bug fixes

  * [Ecto.Association] Ensure we delete an association before inserting when replacing on `has_one`
  * [Ecto.Query] Do not allow interpolated `nil` in literal keyword list when building query
  * [Ecto.Query] Do not remove literals from combinations, otherwise UNION/INTERSECTION queries may not match the nummber of values in `select`
  * [Ecto.Query] Do not attempt to merge at compile-time non-keyword lists given to `select_merge`
  * [Ecto.Repo] Do not override `:through` associations on preload unless forcing
  * [Ecto.Repo] Make sure prefix option cascades to combinations and recursive queries
  * [Ecto.Schema] Use OS time without drift when generating timestamps
  * [Ecto.Type] Allow any datetime in `datetime_add`

## v3.1.7 (2019-06-27)

### Bug fixes

  * [Ecto.Changeset] Make sure `put_assoc` with empty changeset propagates on insert

## v3.1.6 (2019-06-19)

### Enhancements

  * [Ecto.Repo] Add `:read_only` repositories
  * [Ecto.Schema] Also validate options given to `:through` associations

### Bug fixes

  * [Ecto.Changeset] Do not mark `put_assoc` from `[]` to `[]` or from `nil` to `nil` as change
  * [Ecto.Query] Remove named binding when exluding joins
  * [mix ecto.gen.repo] Use `:config_path` instead of hardcoding to `config/config.exs`

## v3.1.5 (2019-06-06)

### Enhancements

  * [Ecto.Repo] Allow `:default_dynamic_repo` option on `use Ecto.Repo`
  * [Ecto.Schema] Support `{:fragment, ...}` in the `:where` option for associations

### Bug fixes

  * [Ecto.Query] Fix handling of literals in combinators (union, except, intersection)

## v3.1.4 (2019-05-07)

### Bug fixes

  * [Ecto.Changeset] Convert validation enums to lists before adding them as validation metadata
  * [Ecto.Schema] Properly propragate prefix to join_through source in many_to_many associations

## v3.1.3 (2019-04-30)

### Enhancements

  * [Ecto.Changeset] Expose the enum that was validated against in errors from enum-based validations

## v3.1.2 (2019-04-24)

### Enhancements

  * [Ecto.Query] Add support for `type+over`
  * [Ecto.Schema] Allow schema fields to be excluded from queries

### Bug fixes

  * [Ecto.Changeset] Do not list a field as changed if it is updated to its original value
  * [Ecto.Query] Keep literal numbers and bitstring in subqueries and unions
  * [Ecto.Query] Improve error message for invalid `type/2` expression
  * [Ecto.Query] Properly count interpolations in `select_merge/2`

## v3.1.1 (2019-04-04)

### Bug fixes

  * [Ecto] Do not require Jason (i.e. it should continue to be an optional dependency)
  * [Ecto.Repo] Make sure `many_to_many` and `Ecto.Multi` work with dynamic repos

## v3.1.0 (2019-04-02)

v3.1 requires Elixir v1.5+.

### Enhancements

  * [Ecto.Changeset] Add `not_equal_to` option for `validate_number`
  * [Ecto.Query] Improve error message for missing `fragment` arguments
  * [Ecto.Query] Improve error message on missing struct key for structs built in `select`
  * [Ecto.Query] Allow dynamic named bindings
  * [Ecto.Repo] Add dynamic repository support with `Ecto.Repo.put_dynamic_repo/1` and `Ecto.Repo.get_dynamic_repo/0` (experimental)
  * [Ecto.Type] Cast naive_datetime/utc_datetime strings without seconds

### Bug fixes

  * [Ecto.Changeset] Do not run `unsafe_validate_unique` query unless relevant fields were changed
  * [Ecto.Changeset] Raise if an unknown field is given on `Ecto.Changeset.change/2`
  * [Ecto.Changeset] Expose the type that was validated in errors generated by `validate_length/3`
  * [Ecto.Query] Add support for `field/2` as first element of `type/2` and alias as second element of `type/2`
  * [Ecto.Query] Do not attempt to assert types of named bindings that are not known at compile time
  * [Ecto.Query] Properly cast boolean expressions in select
  * [Mix.Ecto] Load applications during repo lookup so their app environment is available

### Deprecations

  * [Ecto.LogEntry] Fully deprecate previously soft deprecated API

## v3.0.7 (2019-02-06)

### Bug fixes

  * [Ecto.Query] `reverse_order` reverses by primary key if no order is given

## v3.0.6 (2018-12-31)

### Enhancements

  * [Ecto.Query] Add `reverse_order/1`

### Bug fixes

  * [Ecto.Multi] Raise better error message on accidental rollback inside `Ecto.Multi`
  * [Ecto.Query] Properly merge deeply nested preloaded joins
  * [Ecto.Query] Raise better error message on missing select on schemaless queries
  * [Ecto.Schema] Fix parameter ordering in assoc `:where`

## v3.0.5 (2018-12-08)

### Backwards incompatible changes

  * [Ecto.Schema] The `:where` option added in Ecto 3.0.0 had a major flaw and it has been reworked in this version. This means a tuple of three elements can no longer be passed to `:where`, instead a keyword list must be given. Check the "Filtering associations" section in `has_many/3` docs for more information

### Bug fixes

  * [Ecto.Query] Do not raise on lists of tuples that are not keywords. Instead, let custom Ecto.Type handle them
  * [Ecto.Query] Allow `prefix: nil` to be given to subqueries
  * [Ecto.Query] Use different cache keys for unions/intersections/excepts
  * [Ecto.Repo] Fix support for upserts with `:replace` without a schema
  * [Ecto.Type] Do not lose precision when casting `utc_datetime_usec` with a time zone different than Etc/UTC

## v3.0.4 (2018-11-29)

### Enhancements

  * [Decimal] Bump decimal dependency
  * [Ecto.Repo] Remove unused `:pool_timeout`

## v3.0.3 (2018-11-20)

### Enhancements

  * [Ecto.Changeset] Add `count: :bytes` option in `validate_length/3`
  * [Ecto.Query] Support passing `Ecto.Query` in `Ecto.Repo.insert_all`

### Bug fixes

  * [Ecto.Type] Respect adapter types when loading/dumping arrays and maps
  * [Ecto.Query] Ensure no bindings in order_by when using combinations in `Ecto.Query`
  * [Ecto.Repo] Ensure adapter is compiled (instead of only loaded) before invoking it
  * [Ecto.Repo] Support new style child spec from adapters

## v3.0.2 (2018-11-17)

### Bug fixes

  * [Ecto.LogEntry] Bring old Ecto.LogEntry APIs back for compatibility
  * [Ecto.Repo] Consider non-joined fields when merging preloaded assocs only at root
  * [Ecto.Repo] Take field sources into account in :replace_all_fields upsert option
  * [Ecto.Type] Convert `:utc_datetime` to `DateTime` when sending it to adapters

## v3.0.1 (2018-11-03)

### Bug fixes

  * [Ecto.Query] Ensure parameter order is preserved when using more than 32 parameters
  * [Ecto.Query] Consider query prefix when planning association joins
  * [Ecto.Repo] Consider non-joined fields as unique parameters when merging preloaded query assocs

## v3.0.0 (2018-10-29)

Note this version includes changes from `ecto` and `ecto_sql` but in future releases all `ecto_sql` entries will be listed in their own CHANGELOG.

### Enhancements

  * [Ecto.Adapters.MySQL] Add ability to specify cli_protocol for `ecto.create` and `ecto.drop` commands
  * [Ecto.Adapters.PostgreSQL] Add ability to specify maintenance database name for PostgreSQL adapter for `ecto.create` and `ecto.drop` commands
  * [Ecto.Changeset] Store constraint name in error metadata for constraints
  * [Ecto.Changeset] Add `validations/1` and `constraints/1` instead of allowing direct access on the struct fields
  * [Ecto.Changeset] Add `:force_update` option when casting relations, to force an update even if there are no changes
  * [Ecto.Migration] Migrations now lock the migrations table in order to avoid concurrent migrations in a cluster. The type of lock can be configured via the `:migration_lock` repository configuration and defaults to "FOR UPDATE" or disabled if set to nil
  * [Ecto.Migration] Add `:migration_default_prefix` repository configuration
  * [Ecto.Migration] Add reversible version of `remove/2` subcommand
  * [Ecto.Migration] Add support for non-empty arrays as defaults in migrations
  * [Ecto.Migration] Add support for logging notices/alerts/warnings when running migrations (only supported by Postgres currently)
  * [Ecto.Migrator] Warn when migrating and there is a higher version already migrated in the database
  * [Ecto.Multi] Add support for anonymous functions in `insert/4`, `update/4`, `insert_or_update/4`, and `delete/4`
  * [Ecto.Query] Support tuples in `where` and `having`, allowing queries such as `where: {p.foo, p.bar} > {^foo, ^bar}`
  * [Ecto.Query] Support arithmetic operators in queries as a thin layer around the DB functionality
  * [Ecto.Query] Allow joins in queries to be named via `:as` and allow named bindings
  * [Ecto.Query] Support excluding specific join types in `exclude/2`
  * [Ecto.Query] Allow virtual field update in subqueries
  * [Ecto.Query] Support `coalesce/2` in queries, such as `select: coalesce(p.title, p.old_title)`
  * [Ecto.Query] Support `filter/2` in queries, such as `select: filter(count(p.id), p.public == true)`
  * [Ecto.Query] The `:prefix` and `:hints` options are now supported on both `from` and `join` expressions
  * [Ecto.Query] Support `:asc_nulls_last`, `:asc_nulls_first`, `:desc_nulls_last`, and `:desc_nulls_first` in `order_by`
  * [Ecto.Query] Allow variables (sources) to be given in queries, for example, useful for invoking functions, such as `fragment("some_function(?)", p)`
  * [Ecto.Query] Add support for `union`, `union_all`, `intersection`, `intersection_all`, `except` and `except_all`
  * [Ecto.Query] Add support for `windows` and `over`
  * [Ecto.Query] Raise when comparing a string with a charlist during planning
  * [Ecto.Repo] Only start transactions if an association or embed has changed, this reduces the overhead during repository operations
  * [Ecto.Repo] Support `:replace_all_except_primary_key` as `:on_conflict` strategy
  * [Ecto.Repo] Support `{:replace, fields}` as `:on_conflict` strategy
  * [Ecto.Repo] Support `:unsafe_fragment` as `:conflict_target`
  * [Ecto.Repo] Support `select` in queries given to `update_all` and `delete_all`
  * [Ecto.Repo] Add `Repo.exists?/2`
  * [Ecto.Repo] Add `Repo.checkout/2` - useful when performing multiple operations in short-time to interval, allowing the pool to be bypassed
  * [Ecto.Repo] Add `:stale_error_field` to `Repo.insert/update/delete` that converts `Ecto.StaleEntryError` into a changeset error. The message can also be set with `:stale_error_message`
  * [Ecto.Repo] Preloading now only sorts results by the relationship key instead of sorting by the whole struct
  * [Ecto.Schema] Allow `:where` option to be given to `has_many`/`has_one`/`belongs_to`/`many_to_many`

### Bug fixes

  * [Ecto.Inspect] Do not fail when inspecting query expressions which have a number of bindings more than bindings available
  * [Ecto.Migration] Keep double underscores on autogenerated index names to be consistent with changesets
  * [Ecto.Query] Fix `Ecto.Query.API.map/2` for single nil column with join
  * [Ecto.Migration] Ensure `create_if_not_exists` is properly reversible
  * [Ecto.Repo] Allow many_to_many associations to be preloaded via a function (before the behaviour was erratic)
  * [Ecto.Schema] Make autogen ID loading work with custom type
  * [Ecto.Schema] Make `updated_at` have the same value as `inserted_at`
  * [Ecto.Schema] Ensure all fields are replaced with `on_conflict: :replace_all/:replace_all_except_primary_key` and not only the fields sent as changes
  * [Ecto.Type] Return `:error` when casting NaN or infinite decimals
  * [mix ecto.migrate] Properly run migrations after ECTO_EDITOR changes
  * [mix ecto.migrations] List migrated versions even if the migration file is deleted
  * [mix ecto.load] The task now fails on SQL errors on Postgres

### Deprecations

Although Ecto 3.0 is a major bump version, the functionality below emits deprecation warnings to ease the migration process. The functionality below will be removed in future Ecto 3.1+ releases.

  * [Ecto.Changeset] Passing a list of binaries to `cast/3` is deprecated, please pass a list of atoms instead
  * [Ecto.Multi] `Ecto.Multi.run/3` now receives the repo in which the transaction is executing as the first argument to functions, and the changes so far as the second argument
  * [Ecto.Query] `join/5` now expects `on: expr` as last argument instead of simply `expr`. This was done in order to properly support the `:as`, `:hints` and `:prefix` options
  * [Ecto.Repo] The `:returning` option for `update_all` and `delete_all` has been deprecated as those statements now support `select` clauses
  * [Ecto.Repo] Passing `:adapter` via config is deprecated in favor of passing it on `use Ecto.Repo`
  * [Ecto.Repo] The `:loggers` configuration is deprecated in favor of "Telemetry Events"

### Backwards incompatible changes

  * [Ecto.DateTime] `Ecto.Date`, `Ecto.Time` and `Ecto.DateTime` were previously deprecated and have now been removed
  * [Ecto.DataType] `Ecto.DataType` protocol has been removed
  * [Ecto.Migration] Automatically inferred index names may differ in Ecto v3.0 for indexes on complex column names
  * [Ecto.Multi] `Ecto.Multi.run/5` now receives the repo in which the transaction is executing as the first argument to functions, and the changes so far as the second argument
  * [Ecto.Query] A `join` no longer wraps `fragment` in parentheses. In some cases, such as common table expressions, you will have to explicitly wrap the fragment in parens.
  * [Ecto.Repo] The `on_conflict: :replace_all` option now will also send fields with default values to the database. If you prefer the old behaviour that only sends the changes in the changeset, you can set it to `on_conflict: {:replace, Map.keys(changeset.changes)}` (this change is also listed as a bug fix)
  * [Ecto.Repo] The repository operations are no longer called from association callbacks - this behaviour was not guaranteed in previous versions but we are listing as backwards incompatible changes to help with users relying on this behaviour
  * [Ecto.Repo] `:pool_timeout` is no longer supported in favor of a new queue system described in `DBConnection.start_link/2` under "Queue config". For most users, configuring `:timeout` is enough, as it now includes both queue and query time
  * [Ecto.Schema] `:time`, `:naive_datetime` and `:utc_datetime` no longer keep microseconds information. If you want to keep microseconds, use `:time_usec`, `:naive_datetime_usec`, `:utc_datetime_usec`
  * [Ecto.Schema] The `@schema_prefix` option now only affects the `from`/`join` of where the schema is used and no longer the whole query
  * [Ecto.Schema.Metadata] The `source` key no longer returns a tuple of the schema_prefix and the table/collection name. It now returns just the table/collection string. You can now access the schema_prefix via the `prefix` key.
  * [Mix.Ecto] `Mix.Ecto.ensure_started/2` has been removed. However, in Ecto 2.2 the  `Mix.Ecto` module was not considered part of the public API and should not have been used but we are listing this for guidance.

### Adapter changes

  * [Ecto.Adapter] Split `Ecto.Adapter` into `Ecto.Adapter.Queryable` and `Ecto.Adapter.Schema` to provide more granular repository APIs
  * [Ecto.Adapter] The `:sources` field in `query_meta` now contains three elements tuples with `{source, schema, prefix}` in order to support `from`/`join` prefixes (#2572)
  * [Ecto.Adapter] The database types `time`, `utc_datetime` and `naive_datetime` should translate to types with seconds precision while the database types `time_usec`, `utc_datetime_usec` and `naive_datetime_usec` should have microseconds precision (#2291)
  * [Ecto.Adapter] The `on_conflict` argument for `insert` and `insert_all` no longer receives a `{:replace_all, list(), atom()}` tuple. Instead, it receives a `{fields :: [atom()], list(), atom()}` where `fields` is a list of atoms of the fields to be replaced (#2181)
  * [Ecto.Adapter] `insert`/`update`/`delete` now receive both `:source` and `:prefix` fields instead of a single `:source` field with both `source` and `prefix` in it (#2490)
  * [Ecto.Adapter.Migration] A new `lock_for_migration/4` callback has been added. It is implemented by default by `Ecto.Adapters.SQL` (#2215)
  * [Ecto.Adapter.Migration] The `execute_ddl` should now return `{:ok, []}` to make space for returning notices/hints/warnings in the future (adapters leveraging `Ecto.Adapters.SQL` do not have to perform any change)
  * [Ecto.Query] The `from` field in `Ecto.Query` now returns a `Ecto.Query.FromExpr` with the `:source` field, unifying the behaviour in `from` and `join` expressions (#2497)
  * [Ecto.Query] Tuple expressions are now supported in queries. For example, `where: {p.foo, p.bar} > {p.bar, p.baz}` should translate to `WHERE (p.foo, p.bar) > (p.bar, p.baz)` in SQL databases. Adapters should be changed to handle `{:{}, meta, exprs}` in the query AST (#2344)
  * [Ecto.Query] Adapters should support the following arithmetic operators in queries `+`, `-`, `*` and `/` (#2400)
  * [Ecto.Query] Adapters should support `filter/2` in queries, as in `select: filter(count(p.id), p.public == true)` (#2487)

## Previous versions

  * See the CHANGELOG.md [in the v2.2 branch](https://github.com/elixir-ecto/ecto/blob/v2.2/CHANGELOG.md)
