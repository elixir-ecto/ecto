# Changelog for v3.0

## Highlights

This is a new major release for Ecto v3.0. Despite the major number, this is a small release with the main goal of removing the previously deprecated Ecto datetime types in favor of the Calendar types that ship as part of Elixir and updating to the latest JSON handling best practices.

### Calendar types

`Ecto.Date`, `Ecto.Time` and `Ecto.DateTime` no longer exist. Instead developers should use `Date`, `Time`, `DateTime` and `NaiveDateTime` that ship as part of Elixir and are the preferred types since Ecto 2.1. Database adapters have also been standardized to work with Elixir types and they no longer return tuples when developers perform raw queries.

To uniformly support microseconds across all databases, the types `:time`, `:naive_datetime`, `:utc_datetime` will now discard any microseconds information. Ecto v3.0 introduces the types `:time_usec`, `:naive_datetime_usec` and `:utc_datetime_usec` as an alternative for those interested in keeping microseconds. If you want to keep microseconds in your migrations and schemas, you need to configure your repository:

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

`Ecto.Query` got many other exciting features. Such as pairwise comparisons, as in `where: {p.foo, p.bar} > {^foo, ^bar}`, built-in support for `coalesce` and arithmetic operators, `unsafe_fragment` for the rare cases where you really need to generate a SQL expression dynamically, the ability to filter aggregators, as in `select: filter(count(p.id), p.public == true)`, table specific hints in databases like MySQL and MSSQL, and many more.

### Locked migrations

Running migrations will now lock the migrations table, allowing you to concurrently run migrations in a cluster without worrying that two servers will race each other or without running migrations twice.

## v3.0.0-dev (In Progress)

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
  & [Ecto.Migrator] Warn when migrating and there is a higher version already migrated in the database
  * [Ecto.Multi] Add support for anonymous functions in `insert/4`, `update/4`, `insert_or_update/4`, and `delete/4`
  * [Ecto.Query] Add `unsafe_fragment` to queries which allow developers to send dynamically generated fragments to the database that are not checked (and therefore unsafe)
  * [Ecto.Query] Support tuples in `where` and `having`, allowing queries such as `where: {p.foo, p.bar} > {^foo, ^bar}`
  * [Ecto.Query] Support arithmetic operators in queries as a thin layer around the DB functionality
  * [Ecto.Query] Allow joins in queries to be named via `:as` and allow named bindings
  * [Ecto.Query] Support excluding specific join types in `exclude/2`
  * [Ecto.Query] Allow virtual field update in subqueries
  * [Ecto.Query] Support `coalesce/2` in queries, such as `select: coalesce(p.title, p.old_title)`
  * [Ecto.Query] Support `filter/2` in queries, such as `select: filter(count(p.id), p.public == true)`
  * [Ecto.Query] The `:prefix` and `:hints` options are now supported on both `from` and `join` expressions
  * [Ecto.Query] Support `:asc_nulls_last`, `:asc_nulls_first`, `:desc_nulls_last`, and `:desc_nulls_first` in `order_by`
  * [Ecto.Repo] Support `:replace_all_except_primary_key` as `:on_conflict` strategy
  * [Ecto.Repo] Support `{:replace, fields}` as `:on_conflict` strategy
  * [Ecto.Repo] Support `:unsafe_fragment` as `:conflict_target`
  * [Ecto.Repo] Support `select` in queries given to `update_all` and `delete_all`
  * [Ecto.Repo] Add `Repo.exists?/2`
  * [Ecto.Repo] Preloading now only sorts results by the relationship key instead of sorting by the whole struct
  * [Ecto.Schema] Allow `:where` option to be given to `has_many`/`has_one`/`belongs_to`/`many_to_many`. `many_to_many` also supports `:join_through_where`

### Bug fixes

  * [Ecto.Inspect] Do not fail when inspecting query expressions which have a number of bindings more than bindings available
  * [Ecto.Migration] Keep double underscores on autogenerated index names to be consistent with changesets
  * [Ecto.Query] Fix `Ecto.Query.API.map/2` for single nil column with join
  * [Ecto.Type] Return `:error` when casting NaN or infinite decimals
  * [mix ecto.migrations] List migrated versions even if the migration file is deleted
  * [mix ecto.load] The task now fails on SQL errors on Postgres

### Deprecations

  * [Ecto.Changeset] Passing a list of binaries to `cast/3` is deprecated, please pass a list of atoms instead
  * [Ecto.Multi] `Ecto.Multi.run/3` now receives the repo in which the transaction is executing as the first argument to functions, and the changes so far as the second argument
  * [Ecto.Query] `join/5` now expects `on: expr` as last argument instead of simply `expr`. This was done in order to properly support the `:as`, `:hints` and `:prefix` options
  * [Ecto.Repo] The `:returning` option for `update_all` and `delete_all` has been deprecated as those statements now support `select` clauses
  * [Ecto.Repo] Passing `:adapter` via config is deprecated in favor of passing it on `use Ecto.Repo`

### Backwards incompatible changes

  * [Ecto.DateTime] `Ecto.Date`, `Ecto.Time` and `Ecto.DateTime` were previously deprecated and have now been removed
  * [Ecto.DataType] `Ecto.DataType` protocol has been removed
  * [Ecto.Multi] `Ecto.Multi.run/5` now receives the repo in which the transaction is executing as the first argument to functions, and the changes so far as the second argument
  * [Ecto.Schema] `:time`, `:naive_datetime` and `:utc_datetime` no longer keep microseconds information. If you want to keep microseconds, use `:time_usec`, `:naive_datetime_usec`, `:utc_datetime_usec`
  * [Ecto.Schema] The `@schema_prefix` option now only affects the `from`/`join` of where the schema is used and no longer the whole query

### Adapter changes

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
