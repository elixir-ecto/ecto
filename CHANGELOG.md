# Changelog for v3.0

## Highlights

This is a new major release for Ecto v3.0. Despite the major number, this is a small release with the main goal of removing the previously deprecated Ecto datetime types in favor of the Calendar types that ship as part of Elixir.

In other words, `Ecto.Date`, `Ecto.Time` and `Ecto.DateTime` no longer exist. Instead developers should use `Date`, `Time`, `DateTime` and `NaiveDateTime` that ship as part of Elixir and are the preferred types since Ecto 2.1. Database adapters have also been standarized to work with Elixir types and they no longer return tuples when developers perform raw queries.

(TO BE IMPLEMENTED) To uniformly support microseconds across all databases, the types `:time`, `:naive_datetime`, `:utc_datetime` will now discard any microseconds information. Ecto v3.0 introduces the types `:time_usec`, `:naive_datetime_usec` and `:utc_datetime_usec` as an alternative for those interested in keeping microseconds. If you want to keep microseconds in your migrations and schemas, you need to configure your repository:

    config :my_app, MyApp.Repo,
      migration_timestamps: [type: :naive_datetime_usec]

And then in your schema:

    @timestamps_opts [type: :naive_datetime_usec]

Finally, Ecto v3.0 moved the management of the JSON library to adapters. This means that the following configuration will emit a warning:

    config :ecto, :json_library, CustomJSONLib

And should be rewritten as:

    # For Postgres
    config :postgrex, :json_library, CustomJSONLib

    # For MySQL
    config :mariaex, :json_library, CustomJSONLib

This means Ecto no longer requires Ecto-specific extensions on databases such as Postgres which leads to better integration with 3rd party libraries and faster compilation times.

## v3.0.0-dev (In Progress)

### Enhancements

  * [Ecto.Migration] Migrations now lock the migrations table in order to avoid concurrent migrations in a cluster. The type of lock can be configured via the `:migration_lock` repository configuration and defaults to "FOR UPDATE" or disabled if set to nil
  * [Ecto.Query] Add `unsafe_fragment` to queries which allow developers to send dynamicly generated fragments to the database that are not checked (and therefore unsafe)
  * [Ecto.Repo] Allow some query parameters such as `ssl` and `pool_size` to be given in the repository URL
  * [Ecto.Repo] Support `:replace_all_except_primary_key` as `:on_conflict` strategy

### Backwards incompatible changes

  * [Ecto.Multi] `Ecto.Multi.run/3` and `Ecto.Multi.run/5` now receive the repo in which the transaction is executing as the first argument to functions, and the changes so far as the second argument.
  * [Ecto.DateTime] `Ecto.Date`, `Ecto.Time` and `Ecto.DateTime` were previously deprecated and have now been removed
  * [Ecto.Schema] `:time`, `:naive_datetime` and `:utc_datetime` no longer keep microseconds information. If you want to keep microseconds, use `:time_usec`, `:naive_datetime_usec`, `:utc_datetime_usec`

## Previous versions

  * See the CHANGELOG.md [in the v2.2 branch](https://github.com/elixir-ecto/ecto/blob/v2.2/CHANGELOG.md)
