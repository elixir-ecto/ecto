# Multi tenancy with foreign keys

In [Multi tenancy with query prefixes](Multi tenancy with query prefixes.md), we have learned how to set up multi tenant applications by using separate query prefixes, known as DDL Schemas in PostgreSQL and MSSQL and simply a separate database in MySQL.

Each query prefix is isolated, having their own tables and data, which provides the security guarantees we need. On the other hand, such approach for multi tenancy may be too expensive, as each schema needs to be created, migrated, and versioned separately.

Therefore, some applications may prefer a cheaper mechanism for multi tenancy, by relying on foreign keys. The idea here is that most - if not all - resources in the system belong to a tenant. The tenant is typically an organization or a user and all resources have an `org_id` (or `user_id`) foreign key pointing directly to it.

In this guide, we will show how to leverage Ecto constructs to guarantee that all Ecto queries in your application are properly scoped to a chosen `org_id`.

## Adding org_id to read operations

The first step in our implementation is to make the repository aware of `org_id`. We want to allow commands such as:

```elixir
MyApp.Repo.all Post, org_id: 13
```

Where the repository will automatically scope all posts to the organization with `ID=13`. We can achieve this with the `c:Ecto.Repo.prepare_query/3` repository callback:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo, otp_app: :my_app

  require Ecto.Query

  @impl true
  def prepare_query(_operation, query, opts) do
    cond do
      opts[:skip_org_id] || opts[:schema_migration] ->
        {query, opts}

      org_id = opts[:org_id] ->
        {Ecto.Query.where(query, org_id: ^org_id), opts}

      true ->
        raise "expected org_id or skip_org_id to be set"
    end
  end
end
```

Now we can pass `:org_id` to all READ operations, such as `get`, `get_by`, `preload`, etc and all query operations, such `all`, `update_all`, and `delete_all`. Note we have intentionally made the `:org_id` required, with the exception of two scenarios:

  * if you explicitly set `:skip_org_id` to true, it won't require an `:org_id`. This reduces the odds of a developer forgetting to scope their queries, which can accidentally expose private data to other users

  * if the `:schema_migration` option is set. This means the repository operation was issued by Ecto itself when migrating our database and we don't want to apply an `org_id` to them

Still, setting the `org_id` for every operation is cumbersome and error prone. We will be better served if all operations attempt to set an `org_id`.

## Setting `org_id` by default

To make sure our read operations use the `org_id` by default, we will make two additional changes to the repository.

First, we will store the `org_id` in the process dictionary. The process dictionary is a storage that is exclusive to each process. For example, each test in your project runs in a separate process. Each request in a web application runs in a separate process too. Each of these processes have their own dictionary which we will store and read from. Let's add these functions:

```elixir
defmodule MyApp.Repo do
  ...

  @tenant_key {__MODULE__, :org_id}

  def put_org_id(org_id) do
    Process.put(@tenant_key, org_id)
  end

  def get_org_id() do
    Process.get(@tenant_key)
  end
end
```

We added two new functions. The first, `put_org_id`, stores the organization id in the process dictionary. `get_org_id` reads the value in the process dictionary.

You will want to call `put_org_id` on every process before you use the repository. For example, on every request in a web application, as soon as you read the current organization from the request parameter or the session, you should call `MyApp.Repo.put_org_id(params_org_id)`. In tests, you want to explicitly set the `put_org_id` or pass the `:org_id` option as in the previous section.

The second change we need to do is to set the `org_id` as a default option on all repository operations. The value of `org_id` will be precisely the value in the process dictionary. We can do so trivially by implementing the `default_options` callback:

```elixir
defmodule MyApp.Repo do
  ...

  @impl true
  def default_options(_operation) do
    [org_id: get_org_id()]
  end
end
```

With these changes, we will always set the `org_id` field in our Ecto queries, unless we explicitly set `skip_org_id: true` when calling the repository. The only remaining step is to make sure the `org_id` field is not null in your database tables and make sure the `org_id` is set whenever inserting into the database.

To better understand how our database schema should look like, let's discuss some other techniques that we can use to tighten up multi tenant support, especially in regards to associations.

## Working with multi tenant associations

Let's expand our data domain a little bit.

So far we have assumed there is an organization schema. However, instead of naming its primary key `id`, we will name it `org_id`, so `Repo.one(Org, org_id: 13)` just works:

```elixir
defmodule MyApp.Organization do
  use Ecto.Schema

  @primary_key {:org_id, :id, autogenerate: true}
  schema "orgs" do
    field :name
    timestamps()
  end
end
```

Let's also say that you may have multiple posts in an organization and the posts themselves may have multiple comments:

```elixir
defmodule MyApp.Post do
  use Ecto.Schema

  schema "posts" do
    field :title
    field :org_id, :integer
    has_many :comments, MyApp.Comment
    timestamps()
  end
end

defmodule MyApp.Comment do
  use Ecto.Schema

  schema "comments" do
    field :body
    field :org_id, :integer
    belongs_to :post, MyApp.Post
    timestamps()
  end
end
```

One thing to have in mind is that, our `prepare_query` callback will apply to all queries, but it won't apply to joins inside the same query. Therefore, if you write this query:

```elixir
MyApp.Repo.put_org_id(some_org_id)

MyApp.Repo.all(
  from p in Post, join: c in assoc(p, :comments)
)
```

`prepare_query` will apply the `org_id` only to posts but not to the `join`. While this may seem problematic, in practice it is not an issue, because when you insert posts and comments in the database, **they will always have the same `org_id`**. If posts and comments do not have the same `org_id`, then there is a bug: the data either got corrupted or there is a bug in our software when inserting data.

Luckily, we can leverage database's foreign keys to guarantee that the `org_id`s always match between posts and comments. Our first stab at defining these schema migrations would look like this:

```elixir
create table(:orgs, primary_key: false) do
  add :org_id, :bigserial, primary_key: true
  add :name, :string
  timestamps()
end

create table(:posts) do
  add :title, :string

  add :org_id,
      references(:orgs, column: :org_id),
      null: false

  timestamps()
end

create table(:comments) do
  add :body, :string
  add :org_id, references(:orgs), null: false
  add :post_id, references(:posts), null: false
  timestamps()
end
```

So far the only noteworthy change compared to a regular migration is the `primary_key: false` option to the `:orgs` table, as we want to mirror the primary key of `org_id` given to the schema. While the schema above works and guarantees that posts references an existing organization and that comments references existing posts and organizations, it does not guarantee that all posts and their related comments belong to the same organization.

We can tighten up this requirement by using composite foreign keys with the following changes:

```elixir
create unique_index(:posts, [:id, :org_id])

create table(:comments) do
  add :body, :string

  # There is no need to define a reference for org_id
  add :org_id, :integer, null: false

  # Instead define a composite foreign key
  add :post_id,
      references(:posts, with: [org_id: :org_id]),
      null: false

  timestamps()
end
```

Instead of defining both `post_id` and `org_id` as individual foreign keys, we define `org_id` as a regular integer and then we define `post_id+org_id` as a composite foreign key by passing the `:with` option to `Ecto.Migration.references/2`. This makes sure comments point to posts which point to orgs, where all `org_id`s match.

Given composite foreign keys require the referenced keys to be unique, we also defined a unique index on the posts table **before** we defined the composite foreign key.

If you are using PostgreSQL and you want to tighten these guarantees even further, you can pass the `match: :full` option to `references`:

```elixir
references(:posts, with: [org_id: :org_id], match: :full)
```

which will help enforce none of the columns in the foreign key can be `nil`.

## Summary

In this guide, we have changed our repository interface to guarantee our queries are always scoped to an `org_id`, unless we explicitly opt out. We also learned how to leverage database features to enforce the data is always valid.

When it comes to associations, you will want to apply composite foreign keys whenever possible. For example, imagine comments belongs to posts (which belong to an organization) and also to user (which belong to an organization). The comments schema migration should be defined like this:

```elixir
create table(:comments) do
  add :body, :string
  add :org_id, :integer, null: false

  add :post_id,
      references(:posts, with: [org_id: :org_id]),
      null: false

  add :user_id,
      references(:users, with: [org_id: :org_id]),
      null: false

  timestamps()
end
```

As long as all schemas have an `org_id`, all operations will be safely contained by the current tenant.

If by any chance you have schemas that are not tied to an `org_id`, you can even consider keeping them in a separate query prefix or in a separate database altogether, so you keep non-tenant data completely separated from tenant-specific data.
