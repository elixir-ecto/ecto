# Changelog

## v1.1.3

### Enhancements

* Require Postgrex 0.11.0

## v1.1.2

### Bug fixes

* Be restrict on mariaex and postgrex dependencies

## v1.1.1

### Bug fixes

* Remove documentation for unfinished `on_replace` option in `cast_assoc`, `cast_embed`, `put_assoc` and `put_embed`. The option could be given and applied to the changeset but it would never reach the repository, giving the impression it works as expected but ultimately failing in the repository operation

### Deprecations

* Add missing deprecation on `Ecto.Changeset.cast/3`

## v1.1.0

Ecto v1.1.0 brings many improvements and bug fixes.

In particular v1.1.0 deprecates functionality that has been shown by developers to be confusing, unclear or error prone. They include:

* `Ecto.Model`'s callbacks have been deprecated in favor of composing with changesets and of schema serializers
* `Ecto.Model`'s `optimistic_lock/1` has been deprecated in favor of `Ecto.Changeset.optimistic_lock/3`, which gives more fine grained control over the lock by relying on changesets
* Giving a model to `Ecto.Repo.update/2` has been deprecated as it is ineffective and error prone since changes cannot be tracked
* `Ecto.DateTime.local/0` has been deprecated
* The association and embedded functionality from `Ecto.Changeset.cast/4` has been moved to `Ecto.Changeset.cast_assoc/3` and `Ecto.Changeset.cast_embed/3`
* The association and embedded functionality from `Ecto.Changeset.put_change/3` has been moved to `Ecto.Changeset.put_assoc/3` and `Ecto.Changeset.put_embed/3`

Furthermore, the following functionality has been soft-deprecated (they won't emit warnings for now, only on Ecto v2.0):

* `Ecto.Model` has been soft deprecated. `use Ecto.Schema` instead of `use Ecto.Model` and invoke the functions in `Ecto` instead of the ones in `Ecto.Model`

Keep on reading for more general information about this release.

### Enhancements

* Optimize Ecto.UUID encoding/decoding
* Introduce pool timeout and set default value to 15000ms
* Support lists in `Ecto.Changeset.validate_length/3`
* Add `Ecto.DataType` protocol that allows an Elixir data type to be cast to any Ecto type
* Add `Ecto.Changeset.prepare_changes/2` allowing the changeset to be prepared before sent to the storage
* Add `Ecto.Changeset.traverse_errors/2` for traversing all errors in a changeset, including the ones from embeds and associations
* Add `Ecto.Repo.insert_or_update/2`
* Add support for exclusion constraints
* Add support for precision on `Ecto.Time.utc/1` and `Ecto.DateTime.utc/1`
* Support `count(expr, :distinct)` in query expressions
* Support prefixes in `table` and `index` in migrations
* Allow multiple repos to be given to Mix tasks
* Allow optional binding on `Ecto.Query` operations
* Allow keyword lists on `where`, for example: `from Post, where: [published: true]`

### Bug fixes

* Ensure we update embedded models state after insert/update/delete
* Ensure psql does not hang if not password is given
* Allow fragment joins with custom `on` statement

## v1.0.0

* See the CHANGELOG.md in the v1.0 branch
