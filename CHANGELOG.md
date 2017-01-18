# Changelog for v2.1

This is a minor release of Ecto that builds on the foundation established by Ecto 2.

Ecto 2.1 requires Elixir 1.3+.

## Highlights

### Integration with Elixir 1.3 calendar types

Ecto now supports the following native types `:date`, `:time`, `:naive_datetime` and `:utc_datetime` that map to Elixir types `Date`, `Time`, `NaiveDateTime` and `DateTime` respectively. `:naive_datetime` has no timezone information, while `:utc_datetime` expects the data is stored in the database in the "Etc/UTC" timezone.

Ecto 2.1 also changed the defaults in `Ecto.Schema.timestamps/0` to use `:naive_datetime` as type instead of `Ecto.DateTime` and to include microseconds by default. You can revert to the previous defaults by setting the following before your `schema/2` call:

    @timestamps_opts [type: Ecto.DateTime, usec: false]

The old Ecto types (`Ecto.Date`, `Ecto.Time` and `Ecto.DateTime`) are now deprecated.

### New Postgrex extensions

Ecto 2.1 depends on Postgrex 0.13 which defines a new extension system. Therefore passing the `:extensions` option to the repository configuration is no longer supported, instead you must define a type module. Create a new file anywhere in your application with the following:

    Postgrex.Types.define(MyApp.PostgresTypes,
                          [MyExtension.Foo, MyExtensionBar] ++ Ecto.Adapters.Postgres.extensions(),
                          json: Poison)

Once your type module is defined, you can configure the repository to use it:

    config :my_app, MyApp.Repo, types: MyApp.PostgresTypes

### Dynamic through associations

Ecto 2.1 allows developers to dynamically load through associations via the `Ecto.assoc/2` function. For example, to get all authors for all comments for an existing list of posts, one can do:

    posts = Repo.all from p in Post, where: is_nil(p.published_at)
    Repo.all assoc(posts, [:comments, :author])

In fact, we now recommend developers to prefer dynamically loading through associations as they do not require adding fields to the schema.

### Upsert

Ecto 2.1 now supports upserts (insert or update instructions) on both `Ecto.Repo.insert/2` and `Ecto.Repo.insert_all/3` via the `:on_conflict` and `:conflict_target` options.

`:on_conflict` controls how the database behaves when the entry being inserted already matches an existing primary key, unique or exclusion constraint in the database. `:on_conflict` defaults to `:raise` but may be set to `:nothing` or a query that configures how to update the matching entries.

The `:conflict_target` option allows some databases to restrict which fields to check for conflicts, instead of leaving it up for database inference.

Example:

    # Insert it once
    {:ok, inserted} = MyRepo.insert(%Post{title: "inserted"})

    # Insert with the same ID but do nothing on conflicts.
    # Keep in mind that, although this returns :ok, the returned
    # struct may not necessarily reflect the data in the database.
    {:ok, upserted} = MyRepo.insert(%Post{id: inserted.id, title: "updated"},
                                    on_conflict: :nothing)

    # Now let's insert with the same ID but use a query to update
    # a column on conflicts.  As before, although this returns :ok,
    # the returned struct may not necessarily reflect the data in
    # the database. In fact, any operation done on `:on_conflict`
    # won't be automatically mapped to the struct.

    # In Postgres:
    on_conflict = [set: [title: "updated"]]
    {:ok, updated} = MyRepo.insert(%Post{id: inserted.id, title: "updated"},
                                   on_conflict: on_conflict, conflict_target: :id)

    # In MySQL:
    on_conflict = [set: [title: "updated"]]
    {:ok, updated} = MyRepo.insert(%Post{id: inserted.id, title: "updated"},
                                   on_conflict: on_conflict)

### Named subquery fields

Ecto 2.0 introduced subqueries and Ecto 2.1 brings the ability to use maps to name the expressions selected in a subquery, allowing developers to return tables with conflicting fields or with any other complex expression such as fragments or aggregates:

    posts_with_private = from p in Post, select: %{title: p.title, public: not p.private}
    from p in subquery(posts_with_private), where: p.public, select: p

### `or_where` and `or_having`

Ecto 2.1 adds `or_where` and `or_having` that allows developers to add new query filters that combine with the previous expression using `OR`s.

    from(c in City, where: [state: "Sweden"], or_where: [state: "Brazil"])

### Dynamic expressions

Dynamic query expressions allows developers to build queries expression bit by bit so they are later interpolated in a query.

For example, imagine you have a set of conditions you want to build your query on:

    dynamic = false

    dynamic =
      if params["is_public"] do
        dynamic([p], p.is_public or ^dynamic)
      else
        dynamic
      end

    dynamic =
      if params["allow_reviewers"] do
        dynamic([p, a], a.reviewer == true or ^dynamic)
      else
        dynamic
      end

    from query, where: ^dynamic

In the example above, we were able to build the query expressions bit by bit, using different bindings, and later interpolate it all at once inside the query.

A dynamic expression can always be interpolated inside another dynamic expression or at the root of a `where`, `having`, `update` or a `join`'s `on`.

## v2.1.3 (2017-01-18)

### Bug fixes

  * Avoid ambiguous columns on `insert_all` with `:on_conflict` using inc/push/pull
  * Do not pass `:on_conflict` option to children on `insert`

## v2.1.2 (2017-01-04)

### Bug fixes

  * Also properly deprecate `:datetime` in `modify` migration instructions

## v2.1.1 (2016-12-22)

### Bug fixes

  * Properly deprecate `:datetime` in `add` migration instructions

## v2.1.0 (2016-12-17)

### Enhancements

  * Integrate with Elixir 1.3 calendar types
  * Dynamically load through associations in `Ecto.assoc/2`
  * Add the `:on_conflict` and `:conflict_target` options to `insert/2` and `insert_all/3` for upserts
  * Add `or_where` and `or_having` to `Ecto.Query` for adding further `where` and `having` clauses combined with an `OR` instead of an `AND`
  * Allow subquery fields to be named, adding support for complex expressions in subqueries as well as the ability to solve conflicts on duplicated fields
  * Support the `:prefix` option through the `Ecto.Repo` API
  * Embeds are no longer required to have a primary key field. Coupled with the new `on_replace: :update` (or `on_replace: :delete`) option, this allows `embeds_one` relationships to be updated (or deleted) even without a primary key. For `embeds_many`, `:on_replace` must be set to `:delete` in case updates are desired, forcing all current embeds to be deleted and replaced by new ones whenever a new list of embeds is set
  * Support `...` to specify all previous bindings up to the next one in the query syntax. For example, `where([p, ..., c], p.status == c.status)` matches `p` to the first binding and `c` to the last one
  * Only check for `nil` values during comparison. This avoids unnecessary restrictions on the query syntax on places `nil` should have been allowed
  * Allow the ordering direction to be set when using expressions with `Ecto.Query.distinct/3`
  * Do not generate Repo transaction functions if the adapter does not support transactions
  * Add `Ecto.Repo.init/2` callback for dynamic configuration
  * Support dynamic query building with `Ecto.Query.dynamic/2`
  * Support interpolating keyword lists inside a `join`'s on
  * Allow passing sigils/attributes to fragment
  * Add `Ecto.Multi.error/3` that forces a multi to error
  * Allow queries containing `where` conditions to be interpolated as a `join` source
  * Add `Repo.stream/2` that returns a stream which streams results from the database
  * Add `Repo.load/2` for loading database values into a schema/struct
  * Validate primary key uniqueness at the repository level for assocs and embeds
  * Support passing `:ownership_timeout` when checking out a sandbox connection
  * Raise error when non-existing field is being validated

### Bug fixes

  * Do not raise if a changeset with `:invalid` params in given to `validate_acceptance`
  * Fix postgres prefixed table rename syntax
  * Do not crash `ecto.create`/`ecto.drop` if the repository is configured with `log: false`
  * Ensure `@schema_prefix` module attribute is respected when querying associations with `Ecto.assoc/2`
  * Do not run transactions for empty `Ecto.Multi`
  * Ensure `validate_confirmation` runs even if source field is missing
  * Correct use of "associated to" to "associated with" in error messages
  * Ensure preloader recurs through `:through` associations using the proper key configurations
  * Do not error when inserting an embed without or with non-default primary key

### Deprecations

  * `Ecto.Date`, `Ecto.Time` and `Ecto.DateTime` are deprecated
  * `:datetime` is deprecated as column type in `Ecto.Migration`, use `:naive_datetime` or `:utc_datetime` instead
  * Deprecate `Ecto.Changeset.cast/4` in favor of `Ecto.Changeset.cast/3` + `Ecto.Changeset.validate_required/3`

## Previous versions

  * See the CHANGELOG.md [in the v2.0 branch](https://github.com/elixir-ecto/ecto/blob/v2.0/CHANGELOG.md)
