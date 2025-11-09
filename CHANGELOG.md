# Changelog for v3.x

## v3.13.5 (2025-11-09)

### Enhancements

  * [Ecto.Query] Support selecting a subset of a subquery as a struct

## v3.13.4 (2025-10-24)

### Bug fixes

  * [Ecto.Changeset] Ensure empty binaries are trimmed
  * [Ecto.Repo] Ensure rollback applies to dynamic repos
  * [Ecto.Type] Properly format `:in` composite types

## v3.13.3 (2025-09-19)

### Enhancements

  * [Ecto.Query] Accept a list of things to exclude in `exclude`

### Bug fixes

  * [Ecto.Query] Allow 2-arity functions as preload function in query
  * [Ecto.Query] Remove soft deprecated literal warning
  * [Ecto.Schema] Do not consider space and newlines as empty for binary types

## v3.13.2 (2025-06-24)

### Bug fixes

  * [Ecto.Query] Fix regression which made queries with multiple joins expensive to compile
  * [Ecto.Repo] Fix detection of missing primary key on associations with only nil entries
  * [Ecto.Query] Fix macro expansion in `over` clause's `order_by`

## v3.13.1 (2025-06-19)

### Bug fixes

  * [Ecto.Repo] Do not automatically apply HOT updates on upsert with `replace`. It is the user responsibility to make sure they do not overlap

## v3.13.0 (2025-06-18)

Requires Elixir v1.14+.

### Enhancements

  * [Ecto] Support Elixir's built-in JSON
  * [Ecto.Enum] Add `Ecto.Enum.cast_value/3`
  * [Ecto.Query] Allow schema to be used for `values` list types
  * [Ecto.Query] Allow strings in `field/2`
  * [Ecto.Query] Add `identifier/1` in queries
  * [Ecto.Query] Add `constant/1` in queries
  * [Ecto.Query] Allow `exclude/2` to remove windows
  * [Ecto.Query] Allow source fields in `json_extract_path`
  * [Ecto.Repo] Add `Ecto.Repo.prepare_transaction/2` user callback
  * [Ecto.Repo] Add `Ecto.Repo.all_by/3`
  * [Ecto.Repo] Add `Ecto.Repo.transact/2`
  * [Ecto.Repo] Allow HOT updates on upsert queries in Postgres by removing duplicate fields during `replace_all_except`
  * [Ecto.Schema] Support `@schema_redact: :all_except_primary_keys` module attribute

### Bug fixes

  * [Ecto.Query] Allow select merging maps with all nil values
  * [Ecto.Query] `map/2` in queries now always returns a map on joins, even on left joins, for consistency with `from` sources
  * [Ecto.Schema] Fix an issue where Ecto could warn an association did not exist, when it did

### Soft deprecations (no warnings emitted)

  * [Ecto.Repo] `Ecto.Repo.transaction/2` is soft-deprecated in favor of `Ecto.Repo.transact/1`
  * [Ecto.Query.API] `literal/1` is deprecated in favor of `identifier/1`

## v3.12.6 (2025-06-11)

Fix deprecations on Elixir v1.19.

## v3.12.5 (2024-11-28)

### Bug fixes

  * [Ecto.Query] Raise when empty list is given to `values/2`
  * [Ecto.Query] Fix inspecting `dynamic/2` with interpolated named bindings
  * [Ecto.Query] Plan sources before creating plan_subquery closure
  * [Ecto.Repo] Remove read-only changes from returned record during insert/update
  * [Ecto.Repo] Cascade `:allow_stale` options to assocs

## v3.12.4 (2024-10-07)

### Enhancements

  * [Ecto.Repo] Document new `:pool_count` option

### Bug fixes

  * [Ecto.Repo] Make `Ecto.Repo.reload` respect `source`

## v3.12.3 (2024-09-06)

### Bug fixes

  * [Ecto.Changeset]  Allow associations to be cast/put inside of embedded schema changesets

## v3.12.2 (2024-08-25)

### Bug fixes

  * [Ecto.Query] Allow `:prefix` to be set to any term
  * [Ecto.Repo] Avoid overwriting ssl opts from url if already set in config

## v3.12.1 (2024-08-13)

### Enhancements

  * [Ecto.Type] Add `Ecto.Type.parameterized?/2`

### Bug fixes

  * [Ecto.Enum] Fix dialyzer specification
  * [Ecto.Query] Remove incorrect subquery parameter check

## v3.12.0 (2024-08-12)

### Enhancements

  * [Ecto.Changeset] Allow `{message, opts}` to be given as message for several validation APIs
  * [Ecto.Query] Introduce `is_named_binding` guard
  * [Ecto.Query] Subqueries are now supported in `distinct`, `group_by`, `order_by` and `window` expressions
  * [Ecto.Query] Allow `select_merge` to be used in more `insert_all` and subquery operations by merging distinct fields
  * [Ecto.Query] Allow literal maps inside `dynamic/2`
  * [Ecto.Query] Support macro expansion at the root level of `order_by`
  * [Ecto.Query] Support preloading subquery sources in `from` and `join`
  * [Ecto.Query] Allow map updates with dynamic values in `select`
  * [Ecto.Query] Allow any data structure that implements the Enumerable protocol on the right side of `in`
  * [Ecto.Repo] Support 2-arity preload functions that receive ids and the association metadata
  * [Ecto.Repo] Allow HOT updates on upsert queries in Postgres by removing duplicate fields during `replace_all`
  * [Ecto.Repo] `insert_all` supports queries with only source
  * [Ecto.Repo] `insert_all` supports queries with the update syntax
  * [Ecto.Repo] Support `:allow_stale` on Repo struct/changeset operations
  * [Ecto.Schema] Allow schema fields to be read-only via `:writable` option
  * [Ecto.Schema] Add `:defaults_to_struct` option to `embeds_one`
  * [Ecto.Schema] Support `:duration` type which maps to Elixir v1.17 duration
  * [Ecto.Type] Bubble up custom cast errors of the inner type for `{:map, type}` and `{:array, type}`
  * [Ecto.Type] Add `Ecto.Type.cast!/2`

### Bug fixes

  * [Ecto.Query] Ignore query prefix in CTE sources
  * [Ecto.Query] Fix a bug of `preload` when a through association is used in a join and has a nested separate query preload. Now the association chain is no longer preloaded and we simply preload directly onto the loaded through association.
  * [Ecto.Query] Fix inspection when select has `map/struct` modifiers
  * [Ecto.Query] Disable query cache for `values` lists
  * [Ecto.Repo] Convert fields to their sources in `insert_all`
  * [Ecto.Repo] Raise if empty list is given to `{:replace, fields}`
  * [Ecto.Repo] Validate `:prefix` is a string/binary, warn otherwise
  * [Ecto.Repo] Remove compile dependency on `:preload_order` MFA in `has_many`

### Adapter changes

  * `distinct`, `group_by`, `order_by` and `window` expressions use the new `Ecto.Query.ByExpr`
    struct rather than the old `Ecto.Query.QueryExpr` struct

### Potential incompatibilities

  * [Ecto.Changeset] Associations inside embeds have always been read-only. We now raise if you try to cast them inside a changeset (this was reverted in v3.12.3)
  * [Ecto.ParameterizedType] Parameterized types are now represented internally as `{:parameterized, {mod, state}}`. While this representation is private, projects may have been relying on it, and therefore they need to adapt accordingly. Use `Ecto.ParameterizedType.init/2` to instantiate parameterized types.
  * [Ecto.Query] Drop `:array_join` join type. It was added for Clickhouse support but it is no longer used
  * [Ecto.Query] Validate `:prefix` is a string/binary (this was reverted in v3.12.2)

## v3.11.2 (2024-03-07)

### Bug fixes

  * [Ecto.Query] Fix compatibility with upcoming Elixir v1.17
  * [Ecto.Repo] Do not hide failures when preloading if the parent process is trapping exits

## v3.11.1 (2023-12-07)

### Enhancements

  * [Ecto.Query] Allow module attributes to be given to `in` operator

### Bug fixes

  * [Ecto.Query] Fix interpolating strings and atoms as map keys
  * [Ecto.Query] Plan subqueries in `having`
  * [Ecto.Query] Fix late binding with composite types

## v3.11.0 (2023-11-14)

### Enhancements

  * [Ecto.Association] Allow `preload_order` to take MFAs for `many_to_many` associations. This allows ordering by the join table
  * [Ecto.Query] Add `:operation` option to `with_cte/3`. This allows CTEs to perform updates and deletes
  * [Ecto.Query] Support `splice(^...)` in `fragment`
  * [Ecto.Query] Add `prepend_order_by/3`
  * [Ecto.Query] Allow `selected_as/1` and `selected_as/2` to take interpolated names
  * [Ecto.Query] Allow map update syntax to work with `nil` values in `select`
  * [Ecto.Query] Allow hints to inject SQL using `unsafe_fragment`
  * [Ecto.Query] Support `values/2` lists
  * [Ecto.Repo] Add `:on_preload_spawn` option to `preload/3`
  * [Ecto.Schema] Support `:load_in_query` option for embeds
  * [Ecto.Schema] Support `:returning` option for delete

### Bug fixes

  * [Ecto.Association] Ensure parent prefix is passed to `on_delete` queries
  * [Ecto.Changeset] Ensure duplicate primary keys are always detected for embeds
  * [Ecto.Embedded] Raise `ArgumentError` when specifying an autogenerated `:id` primary key
  * [Ecto.Query] Ensure subquery selects generate unique cache keys
  * [Ecto.Query] Raise on literal non-base binary/uuids in query
  * [Ecto.Repo] Reset `belongs_to` association if foreign key update results in a mismatch

### Adapter changes

  * Adapters now receive `nil` for encoding/decoding
  * Adapters now receive `type` instead of `{:maybe, type}` as the first argument to `loaders/2`

### Deprecations

  * [Ecto.Query] Keyword hints are no longer supported. Please use `unsafe_fragment` inside of hints instead

## v3.10.3 (2023-07-07)

### Enhancements

  * [Ecto.Query] Allow dynamic `field/2` in `type/2`

### Bug fixes

  * [Ecto.Changesets] Limit the largest integer to less than 32 digits
  * [Ecto.Type] Limit the largest integer to less than 32 digits

## v3.10.2 (2023-06-07)

### Enhancements

  * [Ecto.Changeset] Support a three-arity function with position on `cast_assoc` and `cast_embed`
  * [Ecto.Changeset] Add support for maps in `validate_length/3`
  * [Ecto.Changeset] Add `:nulls_distinct` option to `unsafe_validate_unique`
  * [Ecto.Query] Support `array_join` type for ClickHouse adapter
  * [Ecto.Query.API] Support parameterized and custom map types in json path validation

### Bug fixes

  * [Ecto.Repo] Respect parent prefix in `Repo.aggregate`
  * [Ecto.Query.API] Fix late binding in `json_extract_path`

### Deprecations

  * Deprecate MFAs on `:with`

## v3.10.1 (2023-04-12)

### Bug fixes

  * [Ecto.Changeset] Consider `sort_param` even if the relation param was not given
  * [Ecto.Query] Correct typespec to avoid Dialyzer warnings

## v3.10.0 (2023-04-10)

This release contains many improvements to Ecto.Changeset, functions like `Ecto.Changeset.changed?/2` and `field_missing?/2` will help make your code more expressive. Improvements to association and embed handling will also make it easier to manage more complex forms, especially those embedded within Phoenix.LiveView applications.

On the changeset front, note this release unifies the handling of empty values between `cast/4` and `validate_required/3`. **If you were setting `:empty_values` in the past and you want to preserve this new behaviour throughout, you may want to update your code** from this:

    Ecto.Changeset.cast(changeset, params, [:field1, :field2], empty_values: ["", []])

to:

    empty_values = [[]] ++ Ecto.Changeset.empty_values()
    Ecto.Changeset.cast(changeset, params, [:field1, :field2], empty_values: empty_values)

Queries have also been improved to support LIMIT WITH TIES as well as materialized CTEs.

### Enhancements

  * [Ecto.Changeset] Add `get_assoc`/`get_embed`
  * [Ecto.Changeset] Add `field_missing?/2`
  * [Ecto.Changeset] Add `changed?/2` and `changed?/3` with predicates support
  * [Ecto.Changeset] Allow `Regex` to be used in constraint names for exact matches
  * [Ecto.Changeset] Allow `:empty_values` option in `cast/4` to include a function which must return true if the value is empty
  * [Ecto.Changeset] `cast/4` will by default consider strings made only of whitespace characters to be empty
  * [Ecto.Changeset] Add support for `:sort_param` and `:drop_param` on `cast_assoc` and `cast_embed`
  * [Ecto.Query] Support materialized option in CTEs
  * [Ecto.Query] Support dynamic field inside `json_extract_path`
  * [Ecto.Query] Support interpolated values for from/join prefixes
  * [Ecto.Query] Support ties in limit expressions through `with_ties/3`
  * [Ecto.Schema] Add `:autogenerate_fields` to the schema reflection API
  * [Ecto.ParameterizedType] Add optional callback `format/1`

### Bug fixes

  * [Ecto.Changeset] Make unsafe validate unique exclude primary key only for loaded schemas
  * [Ecto.Changeset] Raise when change provided to `validate_format/4` is not a string
  * [Ecto.Query] Fix bug in `json_extract_path` where maps were not allowed to be nested inside of embeds
  * [Ecto.Schema] Allow inline embeds to overwrite conflicting aliases

## v3.9.6 (2023-07-07)

### Enhancements

  * [Ecto.Query] Allow dynamic `field/2` in `type/2`

### Bug fixes

  * [Ecto.Changesets] Limit the largest integer to less than 32 digits
  * [Ecto.Type] Limit the largest integer to less than 32 digits

## v3.9.5 (2023-03-22)

### Bug fixes

  * [Ecto.Query] Rename `@opaque dynamic` type to `@opaque dynamic_expr` to avoid conflicts with Erlang/OTP 26

## v3.9.4 (2022-12-21)

### Bug fixes

  * [Ecto.Query] Fix regression with interpolated preloads introduced in v3.9.3

## v3.9.3 (2022-12-20)

### Enhancements

  * [Ecto] Add `reset_fields/2`
  * [Ecto.Multi] Add `exists?/4` function
  * [Ecto.Repo] Keep url scheme in the repo configuration
  * [Ecto.Query] Add support for cross lateral joins
  * [Ecto.Query] Allow preloads to use `dynamic/2`
  * [Ecto.Query.API] Allow the entire path to be interpolated in `json_extract_path/2`

## v3.9.2 (2022-11-18)

### Enhancements

 * [Ecto.Query] Allow `selected_as` inside CTE
 * [Ecto.Query] Allow `selected_as` to be used in subquery

### Bug fixes

  * [Ecto.Repo] Fix preloading through associations on `nil`
  * [Ecto.Query] Fix select merging a `selected_as` field into a source

## v3.9.1 (2022-10-06)

### Enhancements

  * [Ecto.Query] Allow `selected_as` at the root of `dynamic/2`
  * [Ecto.Query] Allow `selected_as` to be used with `type/2`
  * [Ecto.Query] Allow `selected_as` to be used with `select_merge`

### Bug fixes

  * [Ecto.Changeset] Reenable support for embedded schemas in `unsafe_validate_unique/4`
  * [Ecto.Query] Ensure `join_where` conditions preload correctly in `many_to_many` or with queries with one or many joins

## v3.9.0 (2022-09-27)

### Enhancements

  * [Ecto.Changeset] Add `:force_changes` option to `cast/4`
  * [Ecto.Enum] Allow enum fields to be embed either as their values or their dumped versions
  * [Ecto.Query] Support `^%{field: dynamic(...)}` in `select` and `select_merge`
  * [Ecto.Query] Support `%{field: subquery(...)}` in `select` and `select_merge`
  * [Ecto.Query] Support select aliases through `selected_as/1` and `selected_as/2`
  * [Ecto.Query] Allow `parent_as/1` in `type/2`
  * [Ecto.Query] Add `with_named_binding/3`
  * [Ecto.Query] Allow fragment sources in keyword queries
  * [Ecto.Repo] Support `idle_interval` query parameter in connection URL
  * [Ecto.Repo] Log human-readable UUIDs by using pre-dumped query parameters
  * [Ecto.Schema] Support preloading associations in embedded schemas

### Bug fix

  * [Ecto.Changeset] Raise when schemaless changeset or embedded schema is used in `unsafe_validate_unique/4`
  * [Ecto.Query] Respect virtual field type in subqueries
  * [Ecto.Query] Don't select struct fields overridden with `nil`
  * [Ecto.Query] Fix `select_merge` not tracking `load_in_query: false` field
  * [Ecto.Query] Fix field source when used in `json_extract_path`
  * [Ecto.Query] Properly build CTEs at compile time
  * [Ecto.Query] Properly order subqueries in `dynamic`
  * [Ecto.Repo] Fix `insert_all` query parameter count when using value queries alongside `placeholder`
  * [Ecto.Repo] Raise if combination query is used in a `many` preload
  * [Ecto.Schema] Ignore associations that aren't loaded on insert

## v3.8.4 (2022-06-04)

### Enhancements

  * [Ecto.Multi] Add `one/2` and `all/2` functions
  * [Ecto.Query] Support `literal(...)` in `fragment`

### Bug fix

  * [Ecto.Schema] Make sure fields are inspected in the correct order in Elixir v1.14+

## v3.8.3 (2022-05-11)

### Bug fix

  * [Ecto.Query] Allow source aliases to be used in `type/2`
  * [Ecto.Schema] Avoid "undefined behaviour/struct" warnings and errors during compilation

## v3.8.2 (2022-05-05)

### Bug fix

  * [Ecto.Adapter] Do not require adapter metadata to be raw maps
  * [Ecto.Association] Respect `join_where` in many to many `on_replace` deletes
  * [Ecto.Changeset] Check if list is in `empty_values` before nested validations

## v3.8.1 (2022-04-27)

### Bug fix

  * [Ecto.Query] Fix regression where a join's on parameter on `update_all` was out of order

## v3.8.0 (2022-04-26)

Ecto v3.8 requires Elixir v1.10+.

### Enhancements

  * [Ecto] Add new Embedded chapter to Introductory guides
  * [Ecto.Changeset] Allow custom `:error_key` in unique_constraint
  * [Ecto.Changeset] Add `:match` option to all constraint functions
  * [Ecto.Query] Support dynamic aliases
  * [Ecto.Query] Allow using `type/2` with virtual fields
  * [Ecto.Query] Suggest alternatives to inexistent fields in queries
  * [Ecto.Query] Support passing queries using subqueries to `insert_all`
  * [Ecto.Repo] Allow `stacktrace: true` so stacktraces are included in telemetry events and logs
  * [Ecto.Schema] Validate options given to schema fields

### Bug fixes

  * [Ecto.Changeset] Address regression on `validate_subset` no longer working with custom array types
  * [Ecto.Changeset] **Potentially breaking change**: Detect `empty_values` inside lists when casting. This may cause issues if you were relying on the casting of empty values (by default, only `""`).
  * [Ecto.Query] Handle atom list sigils in `select`
  * [Ecto.Query] Improve tracking of `select_merge` inside subqueries
  * [Ecto.Repo] Properly handle literals in queries given to `insert_all`
  * [Ecto.Repo] Don't surface persisted data as changes on embed updates
  * [Ecto.Repo] **Potentially breaking change**: Raise if an association doesn't have a primary key and is preloaded in a join query. Previously, this would silently produce the wrong the result in certain circumstances.
  * [Ecto.Schema] Preserve parent prefix on join tables

## v3.7.2 (2022-03-13)

### Enhancements

  * [Ecto.Schema] Add option to skip validations for default values
  * [Ecto.Query] Allow coalesce in `type/2`
  * [Ecto.Query] Support parameterized types in type/2
  * [Ecto.Query] Allow arbitrary parentheses in query expressions

## v3.7.1 (2021-08-27)

### Enhancements

  * [Ecto.Embedded] Make `Ecto.Embedded` public and describe struct fields

### Bug fixes

  * [Ecto.Repo] Make sure parent changeset is included in changes for `insert`/`update`/`delete` when there are errors processing the parent itself

## v3.7.0 (2021-08-19)

### Enhancements

  * [Ecto.Changeset] Add `Ecto.Changeset.traverse_validations/2`
  * [Ecto.Enum] Add `Ecto.Enum.mappings/2` and `Ecto.Enum.dump_values/2`
  * [Ecto.Query] Add support for dynamic `as(^as)` and `parent_as(^as)`
  * [Ecto.Repo] Add stale changeset to `Ecto.StaleEntryError` fields
  * [Ecto.Schema] Add support for `@schema_context` to set context metadata on schema definition

### Bug fixes

  * [Ecto.Changeset] Fix changeset inspection not redacting when embedded
  * [Ecto.Changeset] Use semantic comparison on `validate_inclusion`, `validate_exclusion`, and `validate_subset`
  * [Ecto.Enum] Raise on duplicate values in `Ecto.Enum`
  * [Ecto.Query] Make sure `hints` are included in the query cache
  * [Ecto.Repo] Support placeholders in `insert_all` without schemas
  * [Ecto.Repo] Wrap in a subquery when query given to `Repo.aggregate` has combination
  * [Ecto.Repo] Fix CTE subqueries not finding parent bindings
  * [Ecto.Repo] Return changeset with assocs if any of the assocs are invalid

## v3.6.2 (2021-05-28)

### Enhancements

  * [Ecto.Query] Support macros in `with_cte`
  * [Ecto.Repo] Add `Ecto.Repo.all_running/0` to list all running repos

### Bug fixes

  * [Ecto.Query] Do not omit nil fields in a subquery select
  * [Ecto.Query] Allow `parent_as` to look for an alias all the way up across subqueries
  * [Ecto.Query] Raise if a nil value is given to a query from a nested map parameter
  * [Ecto.Query] Fix `insert_all` when using both `:on_conflict` and `:placeholders`
  * [mix ecto.load] Do not pass `--force` to underlying compile task

## v3.6.1 (2021-04-12)

### Enhancements

  * [Ecto.Changeset] Allow the `:query` option in `unsafe_validate_unique`

### Bug fixes

  * [Ecto.Changeset] Add the relation id in `apply_changes` if the relation key exists (instead of hardcoding it to `id`)

## v3.6.0 (2021-04-03)

### Enhancements

  * [Ecto.Changeset] Support `:repo_opts` in `unsafe_validate_unique`
  * [Ecto.Changeset] Add a validation error if trying to cast a cardinality one embed/assoc with anything other than a map or keyword list
  * [Ecto.Enum] Allow enums to map to custom values
  * [Ecto.Multi] Add `Ecto.Multi.put/3` for directly storing values
  * [Ecto.Query] **Potentially breaking change**: optimize `many_to_many` queries so it no longer load intermediary tables in more occasions. This may cause issues if you are using `Ecto.assoc/2` to load `many_to_many` associations and then trying to access intermediate bindings (which is discouraged but it was possible)
  * [Ecto.Repo] Allow `insert_all` to be called with a query instead of rows
  * [Ecto.Repo] Add `:placeholders` support to `insert_all` to avoid sending the same value multiple times
  * [Ecto.Schema] Support `:preload_order` on `has_many` and `many_to_many` associations
  * [Ecto.UUID] Add bang UUID conversion methods
  * [Ecto.Query] The `:hints` option now accepts dynamic values when supplied as tuples
  * [Ecto.Query] Support `select: map(source, fields)` where `source` is a fragment
  * [Ecto.Query] Allow referring to the parent query in a join's subquery select via `parent_as`
  * [mix ecto] Support file and line interpolation on `ECTO_EDITOR`

### Bug fixes

  * [Ecto.Changeset] Change `apply_changes/1` to add the relation to the `struct.relation_id` if relation struct is persisted
  * [Ecto.Query] Remove unnecessary INNER JOIN in many to many association query
  * [Ecto.Query] Allow parametric types to be interpolated in queries
  * [Ecto.Schema] Raise `ArgumentError` when default has invalid type

## v3.5.8 (2021-02-21)

### Enhancements

  * [Ecto.Query] Support map/2 on fragments and subqueries

## v3.5.7 (2021-02-07)

### Bug fixes

  * [Ecto.Query] Fixes param ordering issue on dynamic queries with subqueries

## v3.5.6 (2021-01-20)

### Enhancements

  * [Ecto.Schema] Support `on_replace: :delete_if_exists` on associations

### Bug fixes

  * [Ecto.Query] Allow unary minus operator in query expressions
  * [Ecto.Schema] Allow nil values on typed maps

## v3.5.5 (2020-11-12)

### Enhancements

  * [Ecto.Query] Add support for subqueries operators: `all`, `any`, and `exists`

### Bug fixes

  * [Ecto.Changeset] Use association source on `put_assoc` with maps/keywords
  * [Ecto.Enum] Add `cast` clause for nil values on `Ecto.Enum`
  * [Ecto.Schema] Allow nested type `:any` for non-virtual fields

## v3.5.4 (2020-10-28)

### Enhancements

  * [mix ecto.drop] Provide `--force-drop` for databases that may support it
  * [guides] Add new "Multi tenancy with foreign keys" guide

### Bug fixes

  * [Ecto.Changeset] Make keys optional in specs
  * [Ecto.Enum] Make sure `values/2` works for virtual fields
  * [Ecto.Query] Fix missing type on CTE queries that select a single field

## v3.5.3 (2020-10-21)

### Bug fixes

  * [Ecto.Query] Do not reset parameter counter for nested CTEs
  * [Ecto.Type] Fix regression where array type with nils could no longer be cast/load/dump
  * [Ecto.Type] Fix CaseClauseError when casting a decimal with a binary remainder

## v3.5.2 (2020-10-12)

### Enhancements

  * [Ecto.Repo] Add Repo.reload/2 and Repo.reload!/2

### Bug fixes

  * [Ecto.Changeset] Fix "__schema__/1 is undefined or private" error while inspecting a schemaless changeset
  * [Ecto.Repo] Invoke `c:Ecto.Repo.default_options/1` per entry-point operation

## v3.5.1 (2020-10-08)

### Enhancements

  * [Ecto.Changeset] Warn if there are duplicate IDs in the parent schema for `cast_assoc/3`/`cast_embed/3`
  * [Ecto.Schema] Allow `belongs_to` to accept options for parameterized types

### Bug fixes

  * [Ecto.Query] Keep field types when using a subquery with source

## v3.5.0 (2020-10-03)

v3.5 requires Elixir v1.8+.

### Bug fixes

  * [Ecto.Changeset] Ensure `:empty_values` in `cast/4` does not automatically propagate to following cast calls. If you want a given set of `:empty_values` to apply to all `cast/4` calls, change the value stored in `changeset.empty_values` instead
  * [Ecto.Changeset] **Potentially breaking change**: Do not force repository updates to happen when using `optimistic_lock`. The lock field will only be incremented if the record has other changes. If no changes, nothing happens.
  * [Ecto.Changeset] Do not automatically share empty values across `cast/3` calls
  * [Ecto.Query] Consider query prefix in cte/combination query cache
  * [Ecto.Query] Allow the entry to be marked as nil when using left join with subqueries
  * [Ecto.Query] Support subqueries inside dynamic expressions
  * [Ecto.Repo] Fix preloading when using dynamic repos and the sandbox in automatic mode
  * [Ecto.Repo] Do not duplicate collections when associations are preloaded for repeated elements

### Enhancements

  * [Ecto.Enum] Add `Ecto.Enum` as a custom parameterized type
  * [Ecto.Query] Allow `:prefix` in `from` to be set to nil
  * [Ecto.Query] Do not restrict subqueries in `where` to map/struct types
  * [Ecto.Query] Allow atoms in query without interpolation in order to support Ecto.Enum
  * [Ecto.Schema] Do not validate uniqueness if there is a prior error on the field
  * [Ecto.Schema] Allow `redact: true` in `field`
  * [Ecto.Schema] Support parameterized types via `Ecto.ParameterizedType`
  * [Ecto.Schema] Rewrite embeds and assocs as parameterized types. This means `__schema__(:type, assoc_or_embed)` now returns a parameterized type. To check if something is an association, use `__schema__(:assocs)` or `__schema__(:embeds)` instead

## v3.4.6 (2020-08-07)

### Enhancements

  * [Ecto.Query] Allow `count/0` on `type/2`
  * [Ecto.Multi] Support anonymous functions in multiple functions

### Bug fixes

  * [Ecto.Query] Consider booleans as literals in unions, subqueries, ctes, etc
  * [Ecto.Schema] Generate IDs for nested embeds

## v3.4.5 (2020-06-14)

### Enhancements

  * [Ecto.Changeset] Allow custom error key in `unsafe_validate_unique`
  * [Ecto.Changeset] Improve performance when casting large params maps

### Bug fixes

  * [Ecto.Changeset] Improve error message for invalid `cast_assoc`
  * [Ecto.Query] Fix inspecting query with fragment CTE
  * [Ecto.Query] Fix inspecting dynamics with aliased bindings
  * [Ecto.Query] Improve error message when selecting a single atom
  * [Ecto.Repo] Reduce data-copying when preloading multiple associations
  * [Ecto.Schema] Do not define a compile-time dependency for schema in `:join_through`

## v3.4.4 (2020-05-11)

### Enhancements

  * [Ecto.Schema] Add `join_where` support to `many_to_many`

## v3.4.3 (2020-04-27)

### Enhancements

  * [Ecto.Query] Support `as/1` and `parent_as/1` for lazy named bindings and to allow parent references from subqueries
  * [Ecto.Query] Support `x in subquery(query)`

### Bug fixes

  * [Ecto.Query] Do not raise for missing assocs if :force is given to preload
  * [Ecto.Repo] Return error from `Repo.delete` on invalid changeset from `prepare_changeset`

## v3.4.2 (2020-04-10)

### Enhancements

  * [Ecto.Changeset] Support multiple fields in `unique_constraint/3`

## v3.4.1 (2020-04-08)

### Enhancements

  * [Ecto] Add `Ecto.embedded_load/3` and `Ecto.embedded_dump/2`
  * [Ecto.Query] Improve error message on invalid JSON expressions
  * [Ecto.Repo] Emit `[:ecto, :repo, :init]` telemetry event upon Repo init

### Bug fixes

  * [Ecto.Query] Do not support JSON selectors on `type/2`

### Deprecations

  * [Ecto.Repo] Deprecate `conflict_target: {:constraint, _}`. It is a discouraged approach and `{:unsafe_fragment, _}` is still available if someone definitely needs it

## v3.4.0 (2020-03-24)

v3.4 requires Elixir v1.7+.

### Enhancements

  * [Ecto.Query] Allow dynamic queries in CTE and improve error message
  * [Ecto.Query] Add `Ecto.Query.API.json_extract_path/2` and JSON path support to query syntax. For example, `posts.metadata["tags"][0]["name"]` will return the name of the first tag stored in the `:map` metadata field
  * [Ecto.Repo] Add new `default_options/1` callback to repository
  * [Ecto.Repo] Support passing `:telemetry_options` to repository operations

### Bug fixes

  * [Ecto.Changeset] Properly add validation annotation to `validate_acceptance`
  * [Ecto.Query] Raise if there is loaded non-empty association data without related key when preloading. This typically means not all fields have been loaded in a query
  * [Ecto.Schema] Show meaningful error in case `schema` is invoked twice in an `Ecto.Schema`

## v3.3.4 (2020-02-27)

### Bug fixes

  * [mix ecto] Do not rely on map ordering when parsing repos
  * [mix ecto.gen.repo] Improve error message when a repo is not given

## v3.3.3 (2020-02-14)

### Enhancements

  * [Ecto.Query] Support fragments in `lock`
  * [Ecto.Query] Handle `nil` in `select_merge` with similar semantics to SQL databases (i.e. it simply returns `nil` itself)

## v3.3.2 (2020-01-28)

### Enhancements

  * [Ecto.Changeset] Only bump optimistic lock in case of success
  * [Ecto.Query] Allow macros in Ecto window expressions
  * [Ecto.Schema] Support `:join_defaults` on `many_to_many` associations
  * [Ecto.Schema] Allow MFargs to be given to association `:defaults`
  * [Ecto.Type] Add `Ecto.Type.embedded_load` and `Ecto.Type.embedded_dump`

### Bug fixes

  * [Ecto.Repo] Ignore empty hostname when parsing database url (Elixir v1.10 support)
  * [Ecto.Repo] Rewrite combinations on Repo.exists? queries
  * [Ecto.Schema] Respect child `@schema_prefix` in `cast_assoc`
  * [mix ecto.gen.repo] Use `config_path` when writing new config in `mix ecto.gen.repo`

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

  * [Ecto.Changeset] Add rollover logic for default incrementer in `optimistic_lock`
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
  * [Ecto.Query] Do not remove literals from combinations, otherwise UNION/INTERSECTION queries may not match the number of values in `select`
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
  * [Ecto.Query] Remove named binding when excluding joins
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
  * [Ecto.Schema] Properly propagate prefix to join_through source in many_to_many associations

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
