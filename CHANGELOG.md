# Changelog

## v1.1.0

Ecto v1.1.0 brings many improvements and bug fixes.

In particular v1.1.0 deprecates functionality that has been shown by developers to be confusing, unclear or error prone. They include:

* `Ecto.Model`'s callbacks have been deprecated in favor of composing with changesets
* `Ecto.Model`'s `optimistic_lock/1` has been deprecated in favor of `Ecto.Changeset.optimistic_lock/3`, which gives more fine grained control over the lock by relying on changesets
* Giving a model to `Ecto.Repo.update/2` has been deprecated as it is ineffective and error prone since changes cannot be tracked

Furthermore, the following functionality has been soft-deprecated (they won't emit warnings for now only on Ecto v2.0):

* `Ecto.Model` has been soft deprecated. `use Ecto.Schema` instead of `use Ecto.Model` and invoke the functions in `Ecto` instead of the ones in `Ecto.Model`

Keep on reading for more general information about this release.

### Enhancements

* Optimize Ecto.UUID encoding/decoding
* Introduce pool timeout and set default value to 15000ms
* Support lists in `Ecto.Changeset.validate_length/3`
* Support `count(expr, :distinct)` in query expressions
* Support prefixes in `table` and `index` in migrations
* Allow multiple repos to be given to Mix tasks
* Allow optional binding on `Ecto.Query` operations
* Allow keyword lists on `where`, for example: `from Post, where: [published: true]`

### Bug fixes

* Ensure we update embedded models state after insert/update/delete

## v1.0.0

* See the CHANGELOG.md in the v1.0 branch
