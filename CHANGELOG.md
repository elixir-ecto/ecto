# Changelog

## v2.0.0

This is a new major release of Ecto that removes previously deprecated features and introduces a series of improvements and features based on `db_connection`.

### Backwards incompatible changes

* `Ecto.StaleModelError` has been renamed to `Ecto.StaleEntryError`
* Array fields no longer default to an empty list `[]`

### Enhancements

* Allow associations and embeds to given on `Repo.insert/2` without wrapping them in a changeset. This will make inserting data to the database in scenarios like testing or seeding simpler and more convenient
* Support expressions in map keys in `select` in queries. Example: `from p in Post, select: %{p.title => p.visitors}`

## v1.1

* See the CHANGELOG.md in the v1.1 branch
