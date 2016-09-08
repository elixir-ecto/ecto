# Changelog for v2.1

This is a minor release of Ecto that builds on the foundation established by Ecto 2.

Ecto 2.1 requires Elixir 1.3+.

## Highlights

### Improved subqueries

Ecto 2.0 introduced subqueries and Ecto 2.1 brings many improvements.

The first of them is the ability to use maps to name the expressions selected in a subquery, allowing developers to return tables with conflicting fields or with any other complex expression such as fragments or aggregates:

    ```elixir
    posts_with_private = from p in Post, select: %{title: p.title, public: not p.private}
    from p in subquery(posts_with_private), where: ..., select: p
    ```

Ecto 2.0 has also added support for subqueries in more expressions, such as `x in subquery` and `exists(subquery)`.

## v2.1.0-dev (2016-00-00)

### Enhancements


### Bug fixes


### Soft deprecations (no warnings emitted)


## Previous versions

  * See the CHANGELOG.md in the v2.0 branch
