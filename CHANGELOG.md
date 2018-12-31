# Changelog for v3.0

## Highlights

This is a new major release for Ecto v3.0. Despite the major version change, we have kept the number of user-facing breaking changes to a minimum, the three main ones being:

  * Split the Ecto repository apart
  * Remove the previously deprecated Ecto datetime types in favor of the Calendar types with explicit microsecond prescision that ship as part of Elixir
  * Update to the latest JSON handling best practices

Besides those changes, there are many exciting new features. We will explore all of those changes and more below.

### Split Ecto into `ecto` and `ecto_sql`

Ecto is broken in two repositories: `ecto` and `ecto_sql`. Since Ecto v2.0, an increased number of developers and teams have been using Ecto for data mapping and validation, without a need for a database. However, adding Ecto to your application would still bring a lot of the SQL baggage, such as adapters, sandboxes and migrations. In Ecto 3.0, we have moved all of the SQL adapters to a separate repository and Ecto now mostly focuses on the four Ecto building blocks: schemas, changesets, queries and repos.

If you are using Ecto with a SQL database, migrating to Ecto 3.0 is very striaght-forward. Instead of:

    {:ecto, "~> 2.2"}

You should now list:

    {:ecto_sql, "~> 3.0"}

If the `application` function in your `mix.exs` file includes an `:applications` key, you will need to add `:ecto_sql` to your list of applications. This does not apply if you are using the `:extra_applications` key.

And that's it!

### Calendar types

`Ecto.Date`, `Ecto.Time` and `Ecto.DateTime` no longer exist. Instead developers should use `Date`, `Time`, `DateTime` and `NaiveDateTime` that ship as part of Elixir and are the preferred types since Ecto 2.1. Odds that you are already using the new types and not the deprecated ones.

Note that database adapters have also been standardized to work with Elixir types and they no longer return tuples when developers perform raw queries or use `Ecto.Query` fragments. For example, in Ecto 2.x:

    iex> Repo.one from u in User, select: fragment("?", u.created_at), limit: 1
    {{2018, 10, 8}, {15, 15, 42, 501011}}

And now in Ecto 3.0:

    iex> Repo.one from u in User, select: fragment("?", u.created_at), limit: 1
    ~N[2018-10-08 15:15:42.501011]

To uniformly support microseconds across all databases, the types `:time`, `:naive_datetime`, `:utc_datetime` will now discard any microseconds information on `Ecto.Changeset.cast/4`. Setting the value directly, either in the struct or via `Ecto.Changeset.change/2` will raise if microseconds are not truncated. Ecto v3.0 introduces the types `:time_usec`, `:naive_datetime_usec` and `:utc_datetime_usec` as an alternative for those interested in keeping microseconds. If you want to keep microseconds in your migrations and schemas, you need to configure your repository:

    config :my_app, MyApp.Repo,
      migration_timestamps: [type: :naive_datetime_usec]

And then in your schema:

    @timestamps_opts [type: :naive_datetime_usec]

### JSON handling

Ecto v3.0 moved the management of the JSON library to adapters. All adapters should default to [`Jason`](https://github.com/michalmuskala/jason).

The following configuration will emit a warning:

    config :ecto, :json_library, CustomJSONLib

And should be rewritten as:

    # For Postgres
    config :postgrex, :json_library, CustomJSONLib

    # For MySQL
    config :mariaex, :json_library, CustomJSONLib

If you want to rollback to Poison, you need to configure your adapter accordingly:

    # For Postgres
    config :postgrex, :json_library, Poison

    # For MySQL
    config :mariaex, :json_library, Poison

We recommend everyone to migrate to Jason. Built-in support for Poison will be removed in future Ecto 3.x releases.

### Named bindings

One of the exciting additions in Ecto v3.0 is the addition of named bindings to make the query composition even more flexible:

    query = Post

    # Filter by the join
    query = from p in query,
              join: c in Comment, as: :comments, where: c.post_id == p.id

    # Extend the query
    query = from [p, comments: c] in query,
              select: {p.title, c.body}

`Ecto.Query` got many other exciting features. Such as pairwise comparisons, as in `where: {p.foo, p.bar} > {^foo, ^bar}`, built-in support for `coalesce` and arithmetic operators, the ability to filter aggregators, as in `select: filter(count(p.id), p.public == true)`, table specific hints in databases like MySQL and MSSQL, unions, intersections, windows, and many more.

### Locked migrations

Running migrations will now lock the migrations table, allowing you to concurrently run migrations in a cluster without worrying that two servers will race each other and run migrations twice.

In order for this safer migration mechanism to work, at least two database connections are necessary when migrating. One is used to lock the "schema_migrations" table and the other one to effectively run the migrations.

A downside of this approach is that migrations cannot run dynamically during test under the `Ecto.Adapters.SQL.Sandbox`, as the sandbox is unable to share a single connection across processes at the exact same time. This approach also conflicts with concurrent indexes, found in PostgreSQL. If you want to run concurrent indexes, you will have to disable the `migration_lock`:

    config :my_app, MyApp.Repo, migration_lock: nil

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
  * [Ecto.Query] Allow variables (sources) to be given in queries, for example, useful for invoking functins, such as `fragment("some_function(?)", p)`
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
