# Changelog for v2.1

This is a minor release of Ecto that builds on the foundation established by Ecto 2.

Ecto 2.1 requires Elixir 1.3+.

## Highlights

### Integration with Elixir 1.3 calendar types

Ecto now supports the following native types `:date`, `:time`, `:naive_datetime` and `:utc_datetime` that map to Elixir types `Date`, `Time`, `NaiveDateTime` and `DateTime` respectively. `:naive_datetime` has no timezone information, while `:utc_datetime` expects the data is stored in the database in the "Etc/UTC" timezone.

Ecto 2.1 also changed the defaults in `Ecto.Schema.timestamps/0` to use `:naive_datetime` as type instead of `Ecto.DateTime` and to include microseconds by default. You can revert to the previous defaults by setting the following before your `schema/2` call:

    @timestamps_opts [type: Ecto.DateTime, usec: false]

The old Ecto types (`Ecto.Date`, `Ecto.Time` and `Ecto.DateTime`) are now deprecated.

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
    from p in subquery(posts_with_private), where: ..., select: p

### `or_where` and `or_having`

Ecto 2.1 adds `or_where` and `or_having` that allows developers to add new query filters using `OR` when combining with previous filters.

    from(c in City, where: [state: "Sweden"], or_where: [state: "Brazil"])

It is also possible to interpolate the whole keyword list to dynamically filter the source using OR filters:

    filters = [state: "Sweden", state: "Brazil"]
    from(c in City, or_where: ^filters)

## v2.1.0-dev (2016-00-00)

### Enhancements

  * Support the `:prefix` option through the `Ecto.Repo` API
  * Embeds are no longer required to have a primary key field. Coupled with the new `on_replace: :update` (or `on_replace: :delete`) option, this allows `embeds_one` relationships to be updated (or deleted) even without a primary key. For `embeds_many`, `:on_replace` must be set to `:delete` in case updates are desired, forcing all current embeds to be deleted and replaced by new ones whenever a new list of embeds is set.
  * Support `...` to specify all previous bindings up to the next one in the query syntax. For example, `where([p, ..., c], p.status == c.status)` matches `p` to the first binding and `c` to the last one.
  * Only check for `nil` values during comparison. This avoids unecessary restrictions on the query syntax on places `nil` should have been allowed
  * Allow the ordering direction to be set when using expressions with `Ecto.Query.distinct/3`

### Deprecations

  * `Ecto.Date`, `Ecto.Time` and `Ecto.DateTime` are deprecated
  * `:datetime` is deprecated as column type in `Ecto.Migration`, use `:naive_datetime` or `:utc_datetime` instead
  * Deprecate `Ecto.Changeset.cast/4` in favor of `Ecto.Changeset.cast/3` + `Ecto.Changeset.validate_required/3`

## Previous versions

  * See the CHANGELOG.md in the v2.0 branch
