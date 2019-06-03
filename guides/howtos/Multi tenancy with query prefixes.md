# Multi tenancy with query prefixes

With Ecto we can run queries in different prefixes using a single pool of database connections. For databases engines such as Postgres, Ecto's prefix [maps to Postgres' DDL schemas](https://www.postgresql.org/docs/current/static/ddl-schemas.html). For MySQL, each prefix is a different database on its own.

Query prefixes may be useful in different scenarios. For example, multi tenant apps running on Postgres would define multiple prefixes, usually one per client, under a single database. The idea is that prefixes will provide data isolation between the different users of the application, guaranteeing either globally or at the data level that queries and commands act on a specific prefix.

Prefixes may also be useful on high-traffic applications where data is partitioned upfront. For example, a gaming platform may break game data into isolated partitions, each named after a different prefix. A partition for a given player is either chosen at random or calculated based on the player information.

While query prefixes were designed with the two scenarios above in mind, they may also be used in other circumstances, which we will explore throughout this chapter. All the examples below assume you are using Postgres. Other databases engines may require slightly different solutions.

## Global prefixes

As a starting point, let's start with a simple scenario: your application must connect to a particular prefix when running in production. This may be due to infrastructure conditions, database administration rules or others.

Let's define a repository and a schema to get started:

```elixir
# lib/repo.ex
defmodule MyApp.Repo do
  use Ecto.Repo, otp_app: :my_app
end

# lib/sample.ex
defmodule MyApp.Sample do
  use Ecto.Schema

  schema "samples" do
    field :name
    timestamps
  end
end
```

Now let's configure the repository:

```elixir
# config/config.exs
config :my_app, MyApp.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "demo",
  hostname: "localhost",
  pool_size: 10
```

And define a migration:

```elixir
# priv/repo/migrations/20160101000000_create_sample.exs
defmodule MyApp.Repo.Migrations.CreateSample do
  use Ecto.Migration

  def change do
    create table(:samples) do
      add :name, :string
      timestamps()
    end
  end
end
```

Now let's create the database, migrate it and then start an IEx session:

```bash
$ mix ecto.create
$ mix ecto.migrate
$ iex -S mix
Interactive Elixir (1.4.0-dev) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> MyApp.Repo.all MyApp.Sample
[]
```

We haven't done anything unusual so far. We created our database instance, made it up to date by running migrations and then successfully made a query against the "samples" table, which returned an empty list.

By default, connections to Postgres' databases run on the "public" prefix. When we run migrations and queries, they are all running against the "public" prefix. However imagine your application has a requirement to run on a particular prefix in production, let's call it "global_prefix".

Luckily Postgres allows us to change the prefix our database connections run on by setting the "schema search path". The best moment to change the search path is right after we setup the database connection, ensuring all of our queries will run on that particular prefix, throughout the connection life-cycle.

To do so, let's change our database configuration in "config/config.exs" and specify an `:after_connect` option. `:after_connect` expects a tuple with module, function and arguments it will invoke with the connection process, as soon as a database connection is established:

```elixir
config :my_app, MyApp.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "demo_dev",
  hostname: "localhost",
  pool_size: 10,
  after_connect: {Postgrex, :query!, ["SET search_path TO global_prefix", []]}
```

Now let's try to run the same query as before:

```bash
$ iex -S mix
Interactive Elixir (1.4.0-dev) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> MyApp.Repo.all MyApp.Sample
** (Postgrex.Error) ERROR (undefined_table): relation "samples" does not exist
```

Our previously successful query now fails because there is no table "samples" under the new prefix. Let's try to fix that by running migrations:

```bash
$ mix ecto.migrate
** (Postgrex.Error) ERROR (invalid_schema_name): no schema has been selected to create in
```

Oops. Now migration says there is no such schema name. That's because Postgres automatically creates the "public" prefix every time we create a new database. If we want to use a different prefix, we must explicitly create it on the database we are running on:

```bash
$ psql -d demo_dev -c "CREATE SCHEMA global_prefix"
```

Now we are ready to migrate and run our queries:

```bash
$ mix ecto.migrate
$ iex -S mix
Interactive Elixir (1.4.0-dev) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> MyApp.Repo.all MyApp.Sample
[]
```

Data in different prefixes are isolated. Writing to the "samples" table in one prefix cannot be accessed by the other unless we change the prefix in the connection or use the Ecto conveniences we will discuss next.

## Per-query and per-struct prefixes

While still configured to connect to the "global_prefix" on `:after_connect`, let's run some queries:

```iex
iex(1) MyApp.Repo.all MyApp.Sample
[]
iex(2) MyApp.Repo.insert %MyApp.Sample{name: "mary"}
{:ok, %MyApp.Sample{...}}
iex(3) MyApp.Repo.all MyApp.Sample
[%MyApp.Sample{...}]
```

The operations above ran on the "global_prefix". Now what happens if we try to run the sample query on the "public" prefix? To do so, let's build a query struct and set the prefix field manually:

```iex
iex(4)> query = Ecto.Queryable.to_query MyApp.Sample
#Ecto.Query<from s in MyApp.Sample>
iex(5)>  MyApp.Repo.all %{query | prefix: "public"}
[]
```

Notice how we were able to change the prefix the query runs on. Back in the default "public" prefix, there is no data.

Ecto also supports the `:prefix` option on all relevant repository operations:

```iex
iex(6)> MyApp.Repo.all MyApp.Sample
[%MyApp.Sample{...}]
iex(7)> MyApp.Repo.all MyApp.Sample, prefix: "public"
[]
```

One interesting aspect of prefixes in Ecto is that the prefix information is carried along each struct returned by a query:

```iex
iex(8) [sample] = MyApp.Repo.all MyApp.Sample
[%MyApp.Sample{}]
iex(9)> Ecto.get_meta(sample, :prefix)
nil
```

The example above returned nil, which means no prefix was specified by Ecto, and therefore the database connection default will be used. In this case, "global_prefix" will be used because of the `:after_connect` callback we added at the beginning of this chapter.

Since the prefix data is carried in the struct, we can use such to copy data from one prefix to the other. Let's copy the sample above from the "global_prefix" to the "public" one:

```iex
iex(10)> public_sample = Ecto.put_meta(sample, prefix: "public")
%MyApp.Sample{}
iex(11)> MyApp.Repo.insert public_sample
{:ok, %MyApp.Sample{}}
iex(12)> [sample] = MyApp.Repo.all MyApp.Sample, prefix: "public"
[%MyApp.Sample{}]
iex(13)> Ecto.get_meta(sample, :prefix)
"public"
```

Now we have data inserted in both prefixes.

Prefixes in queries and structs always cascade. For example, if you run `MyApp.Repo.preload(sample, [:some_association])`, the association will be queried for and loaded in the same prefix as the `sample` struct. If `sample` has associations and you call `MyApp.Repo.insert(sample)` or `MyApp.Repo.update(sample)`, the associated data will also be inserted/updated in the same prefix as `sample`. That's by design to facilitate working with groups of data in the same prefix, and especially because **data in different prefixes must be kept isolated**.

## Migration prefixes

So far we have explored how to set a global prefix using Postgres' and how to set the prefix at the query or struct level. When the global prefix is set, it also changes the prefix migrations run on. However it is also possible to set the prefix through the command line or per table in the migration itself.

For example, imagine you are a gaming company where the game is broken in 128 partitions, named "prefix_1", "prefix_2", "prefix_3" up to "prefix_128". Now, whenever you need to migrate data, you need to migrate data on all different 128 prefixes. There are two ways of achieve that.

The first mechanism is to invoke `mix ecto.migrate` multiple times, once per prefix, passing the `--prefix` option:

```bash
$ mix ecto.migrate --prefix "prefix_1"
$ mix ecto.migrate --prefix "prefix_2"
$ mix ecto.migrate --prefix "prefix_3"
...
$ mix ecto.migrate --prefix "prefix_128"
```

The other approach is by changing each desired migration to run across multiple prefixes. For example:

```elixir
defmodule MyApp.Repo.Migrations.CreateSample do
  use Ecto.Migration

  def change do
    for i <- 1..128 do
      prefix = "prefix_#{i}"
      create table(:samples, prefix: prefix) do
        add :name, :string
        timestamps()
      end

      # Execute the commands on the current prefix
      # before moving on to the next prefix
      flush()
    end
  end
end
```

## Schema prefixes

Finally, Ecto allows you to set a particular schema to run on a specific prefix. Imagine you are building a multi-tenant application. Each client data belongs to a particular prefix, such as "client_foo", "client_bar" and so forth. Yet your application may still rely on a set of tables that is shared across all clients. One of such tables may be exactly the table that maps the Client ID to its database prefix. Let's assume we want to store this data in a prefix named "main":

```elixir
defmodule MyApp.Mapping do
  use Ecto.Schema

  @schema_prefix "main"
  schema "mappings" do
    field :client_id, :integer
    field :db_prefix
    timestamps
  end
end
```

Now running `MyApp.Repo.all MyApp.Mapping` will by default run on the "main" prefix, regardless of the value configured globally on the `:after_connect` callback. Similar will happen to `insert`, `update`, and similar operations, the `@schema_prefix` is used unless the `:prefix` is explicitly changed via `Ecto.put_meta/2` or by passing the `:prefix` option to the repository operation.

Keep in mind, however, that queries run on a single prefix. For example, if `MyApp.Mapping` on prefix "main" depends on a schema named `MyApp.Other` on prefix "another", a query starting with `MyApp.Mapping` will always run on the "main" prefix. By design it is not possible to perform query joins across prefixes. If data belongs to different prefixes, it is best to not couple them structurally nor via queries, in order to **keep data in different prefixes isolated**.

## Summing up

Ecto provides many conveniences for working with querying prefixes. Those conveniences allow developers to configure prefix with different level of granularity:

    global prefixes > schema prefix > query/struct prefixes

This way developers can tackle different scenarios, from production requirements to multi-tenant applications.
