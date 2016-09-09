# Changelog for v2.1

This is a minor release of Ecto that builds on the foundation established by Ecto 2.

Ecto 2.1 requires Elixir 1.3+.

## Highlights

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

  * Embeds are no longer required to have a primary key field. Coupled with the new `on_replace: :update` (or `on_replace: :delete`) option, this allows `embeds_one` relationships to be updated (or deleted) even without a primary key. For `embeds_many`, `:on_replace` must be set to `:delete` in case updates are desired, forcing all current embeds to be deleted and replaced by new ones whenever a new list of embeds is set.

### Bug fixes


### Soft deprecations (no warnings emitted)


## Previous versions

  * See the CHANGELOG.md in the v2.0 branch
