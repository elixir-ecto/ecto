# Changelog

## v2.0.0

This is a new major release of Ecto that removes previously deprecated features and introduces a series of improvements and features based on `db_connection`.

### Highlights

#### Improved association support

Ecto now supports `belongs_to` associations to be cast or changed via changesets, beyond `has_one`, `has_many` and embeds. Not only that, Ecto supports associations and embeds to be defined directly from the struct on insertion. For example, one can call:

    Repo.insert! %Permalink{
      url: "//root",
      post: %Post{
        title: "A permalink belongs to a post which we are inserting",
        comments: [
          %Comment{text: "child 1"},
          %Comment{text: "child 2"},
        ]
      }
    }

This allows developers to easily insert a tree of structs into the database, be it when seeding data for production or during tests.

Finally, Ecto now allows putting existing records in changesets, and the proper changes will be reflected in both structs and the database. For example, you may retrieve the permalink above and associate it to another existing post:

    permalink
    |> Ecto.Changeset.change
    |> Ecto.Changeset.put_assoc(:post, existing_post)
    |> Repo.update!

### Backwards incompatible changes

* `Ecto.StaleModelError` has been renamed to `Ecto.StaleEntryError`
* Array fields no longer default to an empty list `[]`
* Poolboy now expects `:pool_overflow` option instead of `:max_overflow`
* `Repo.insert/2` will now send only non-nil fields from the struct to the storage (in previous versions, all fields from the struct were sent to the database)

### Enhancements

* Support expressions in map keys in `select` in queries. Example: `from p in Post, select: %{p.title => p.visitors}`
* Add support for partial indexes by specifying the `:where` option when defining an index
* Allow dynamic and atom fields to be specified on `group_by` and `distinct`
* Ensure adapters work on native types, guaranteeing adapters compose better with custom types
* Allow the migration table name to be configured

### Bug fixes

* The `:required` option on `cast_assoc`and `cast_embed` will now tag `has_many` and `embeds_many` relationships as missing if they contain an empty list

## v1.1

* See the CHANGELOG.md in the v1.1 branch
