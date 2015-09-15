# Changelog

## v1.1.0

Ecto v1.1.0 brings many improvements and bug fixes.

In particular v1.1.0 deprecates functionality that has been shown by developers to be confusing, unclear or error prone. They include:

* `use Ecto.Model` has been trimmed down to import less functionality out of the box in favor of explicitness
* Given a model to `Repo.update/2` has been deprecated as it is inneffective and error prone since changes cannot be tracked
* `Ecto.Model.put_source/3` provided a confusing API for changing prefix that has been replaced in favor of the clearer and more complete `put_meta/2`

Keep on reading for more general information about this release.

### Enhancements

* Support lists in `Ecto.Changeset.validate_length/3`

### Bug fixes

* ...

## v1.0.0

* See the CHANGELOG.md in the v1.0 branch
