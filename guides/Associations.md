# Ecto Association Guide

This guide assumes you worked through the [Getting Started guide](Getting%20Started.md) and want to learn more about associations.

There are three kinds of associations:

  * one-to-one
  * one-to-many
  * many-to-many

In this tutorial we're going to create a minimal Ecto project then we're going to create basic schemas and migrations, and finally associate the schemas.

## Ecto Setup

First, we're going to create a fresh Ecto project which is going to be used for the rest of the tutorial:

```
$ mix new ecto_assoc --sup
```

Add `ecto` and `postgrex` as dependencies to `mix.exs`

```elixir
# mix.exs
defp deps do
  [{:ecto, "~> 2.0"},
   {:postgrex, "~> 0.11"}]
end
```

Let's generate a repo and create the corresponding DB.

```
$ mix ecto.gen.repo -r EctoAssoc.Repo
```

Make sure the config for the repo is set properly:

```elixir
# config/config.exs
config :ecto_assoc, EctoAssoc.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ecto_assoc_repo",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :ecto_assoc, ecto_repos: [EctoAssoc.Repo]
```

Add the repo as a supervisor within the application's supervision tree:

`Elixir < 1.5.0`:
```elixir
# lib/ecto_assoc/application.exs
def start(_type, _args) do
  import Supervisor.Spec

  children = [
    supervisor(EctoAssoc.Repo, []),
  ]

  ...
```

`Elixir >= 1.5.0`:
```elixir
# lib/ecto_assoc/application.exs
def start(_type, _args) do

  children = [
    EctoAssoc.Repo,
  ]

  ...
```

Finally let's create the DB:

```
$ mix ecto.create
```

## One-to-one

### Prep

Let's start with two schemas that are not yet associated: `User` and `Avatar`.

We will generate the migration for `User`:

```elixir
mix ecto.gen.migration create_user
```

And add some columns:

```elixir
# priv/repo/migrations/*_create_user.exs
defmodule EctoAssoc.Repo.Migrations.CreateUser do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string
      add :email, :string
    end
  end
end
```

And the following schema:

```elixir
# lib/ecto_assoc/user.ex
defmodule EctoAssoc.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :email, :string
  end
end
```

`Avatar` also has its own migration as well:

```
mix ecto.gen.migration create_avatar
```

with the following columns:

```elixir
# priv/repo/migrations/*_create_avatar.exs
defmodule EctoAssoc.Repo.Migrations.CreateAvatar do
  use Ecto.Migration

  def change do
    create table(:avatars) do
      add :nick_name, :string
      add :pic_url, :string
    end
  end
end
```

and the following schema:

```elixir
# lib/ecto_assoc/avatar.ex
defmodule EctoAssoc.Avatar do
  use Ecto.Schema

  schema "avatars" do
    field :nick_name, :string
    field :pic_url, :string
  end
end
```

### Adding Associations

Now we want to associate the user with the avatar and vice-versa:

  * one user has one avatar
  * one avatar belongs to one user

The difference between [`has_one`](Ecto.Schema.html#has_one/3) and [`belongs_to`](Ecto.Schema.html#belongs_to/3) is where the primary key belongs. In this case, we want the "avatars" table to have a "user_id" column, therefore the avatar belongs to the user.

For the `Avatar` we create a migration that adds a `user_id` reference:

```
mix ecto.gen.migration avatar_belongs_to_user
```

with the following steps:

```elixir
# priv/repo/migrations/20161117101812_avatar_belongs_to_user.exs
defmodule EctoAssoc.Repo.Migrations.AvatarBelongsToUser do
  use Ecto.Migration

  def change do
    alter table(:avatars) do
      add :user_id, references(:users)
    end
  end
end
```

This adds a `user_id` column to the DB which references an entry in the users table.

For the `Avatar` we add a `belongs_to` field to the schema:

```elixir
defmodule EctoAssoc.Avatar do
  schema "avatars" do
    field :nick_name, :string
    field :pic_url, :string
    belongs_to :user, EctoAssoc.User  # this was added
  end
end
```

`belongs_to` is a macro which uses a foreign key (in this case `user_id`) to make the associated schema accessible through the avatar. In this case, you can access the user via `avatar.user`.

For the `User` we add a `has_one` field to the schema:

```elixir
# lib/ecto_assoc/user.ex
defmodule EctoAssoc.User do
  schema "users" do
    field :name, :string
    field :email, :string
    has_one :avatar, EctoAssoc.Avatar  # this was added
  end
end
```

`has_one` does not add anything to the DB. The foreign key of the associated schema, `Avatar`, is used to make the avatar available from the user, allowing you to access the avatar via `user.avatar`.

### Persistence

Now let's add data to the DB. Start iex:

```
$ iex -S mix
```

For convenience we alias some modules:

```elixir
iex> alias EctoAssoc.{Repo, User, Avatar}
```

Create a user struct and insert it into the repo:

```elixir
iex> user = %User{name: "John Doe", email: "john.doe@example.com"}
iex> user = Repo.insert!(user)
%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
 avatar: #Ecto.Association.NotLoaded<association :avatar is not loaded>,
 email: "john.doe@example.com", id: 3, name: "John Doe"}
```

This time let's add another user with an avatar association. We can define it directly in the `User` struct in the `:avatar` field:

```elixir
iex> avatar = %Avatar{nick_name: "Elixir", pic_url: "http://elixir-lang.org/images/logo.png"}
iex> user = %User{name: "Jane Doe", email: "jane@example.com", avatar: avatar}
iex> user = Repo.insert!(user)
%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
 avatar: %{__meta__: #Ecto.Schema.Metadata<:loaded, "avatars">,
   __struct__: EctoAssoc.Avatar, id: 2, nick_name: "Elixir",
   pic_url: "http://elixir-lang.org/images/logo.png",
   user: #Ecto.Association.NotLoaded<association :user is not loaded>,
   user_id: 4}, email: "jane@example.com", id: 4, name: "Jane Doe"}
```

Let's verify that it works by retrieving all users and their associated avatars:

```elixir
iex> Repo.all(User) |> Repo.preload(:avatar)
[%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">, avatar: nil,
  email: "john.doe@example.com", id: 3, name: "John Doe"},
 %EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
  avatar: %EctoAssoc.Avatar{__meta__: #Ecto.Schema.Metadata<:loaded, "avatars">,
   id: 2, nick_name: "Elixir", pic_url: "http://elixir-lang.org/images/logo.png",
   user: #Ecto.Association.NotLoaded<association :user is not loaded>,
   user_id: 4}, email: "jane@example.com", id: 4, name: "Jane Doe"}]
```

## One-to-many

### Prep

Let's assume we have two schemas: `User` and `Post`. The `User` schema was defined in the previous section and the `Post` schema will be defined now.

Let's start with the migration:

```
mix ecto.gen.migration create_post
```

with the following columns:

```elixir
# priv/repo/migrations/*_create_post.exs
defmodule EctoAssoc.Repo.Migrations.CreatePost do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :header, :string
      add :body, :string
    end
  end
end
```

and the following schema:

```elixir
# lib/ecto_assoc/post.ex
defmodule EctoAssoc.Post do
  use Ecto.Schema

  schema "posts" do
    field :header, :string
    field :body, :string
  end
end
```

### Adding Associations

Now we want to associate the user with the post and vice-versa:

  * one user has many posts
  * one post belongs to one user

As in `one-to-one` associations, the `belongs_to` reveals on which table the foreign key should be added. For the `Post` we create a migration that adds a `user_id` reference:

```
mix ecto.gen.migration post_belongs_to_user
```

with the following contents:

```elixir
# priv/repo/migrations/*_post_belongs_to_user.exs
defmodule EctoAssoc.Repo.Migrations.PostBelongsToUser do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :user_id, references(:users)
    end
  end
end
```

For the `Post` we add a `belongs_to` field to the schema:

```elixir
defmodule EctoAssoc.Post do
  use Ecto.Schema

  schema "posts" do
    field :header, :string
    field :body, :string
    belongs_to :user, EctoAssoc.User  # this was added
  end
end
```

`belongs_to` is a macro which uses a foreign key (in this case `user_id`) to make the associated schema accessible through the `Post`. The user can be accessed via `post.user`.

For the `User` we add a `has_many` field to the schema:

```elixir
defmodule EctoAssoc.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :email, :string
    has_many :posts, EctoAssoc.Post  # this was added
  end
end
```

[`has_many`](Ecto.Schema.html#has_many/3) does not add anything to the DB. The foreign key of the associated schema, `Post`, is used to make the posts available from the user, allowing all posts for a given to user to be accessed via `user.posts`.

### Persistence

Start iex:

```
$ iex -S mix
```

For convenience we alias some modules:

```elixir
iex> alias EctoAssoc.{Repo, User, Post}
```

Let's create a `User` and store it in the DB:

```elixir
iex> user = %User{name: "John Doe", email: "john.doe@example.com"}
iex> user = Repo.insert!(user)
%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
 email: "john.doe@example.com", id: 1, name: "John Doe",
 posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}
```

Let's build an associated post and store it in the DB. We can take a similar approach as we did in `one_to_one` and directly pass a list of posts in the `posts` field when inserting the user, effectively inserting the user and multiple posts at once.

However, let's try a different approach and use [`Ecto.build_assoc/3`](Ecto.html#build_assoc/3) to build a post that is associated with the existing user we have just defined:

```elixir
iex> post = Ecto.build_assoc(user, :posts, %{header: "Clickbait header", body: "No real content"})
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:built, "posts">,
 body: "No real content", header: "Clickbait header", id: nil,
 user: #Ecto.Association.NotLoaded<association :user is not loaded>, user_id: 1}

iex> Repo.insert!(post)
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
 body: "No real content", header: "Clickbait header", id: 1,
 user: #Ecto.Association.NotLoaded<association :user is not loaded>, user_id: 1}
```

Let's add another post to the user:

```elixir
iex> post = Ecto.build_assoc(user, :posts, %{header: "5 ways to improve your Ecto", body: "Add url of this tutorial"})
iex> Repo.insert!(post)
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
 body: "Add url of this tutorial", header: "5 ways to improve your Ecto",
 id: 2, user: #Ecto.Association.NotLoaded<association :user is not loaded>,
 user_id: 1}
```

Let's see if it worked:

```
iex> Repo.get(User, user.id) |> Repo.preload(:posts)
%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
 email: "john.doe@example.com", id: 1, name: "John Doe",
 posts: [%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
   body: "No real content", header: "Clickbait header", id: 1,
   user: #Ecto.Association.NotLoaded<association :user is not loaded>,
   user_id: 1},
  %EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
   body: "Add url of this tutorial", header: "5 ways to improve your Ecto",
   id: 2, user: #Ecto.Association.NotLoaded<association :user is not loaded>,
   user_id: 1}]}
```

In the example above, `Ecto.build_assoc` received an existing `User` struct, that was already persisted to the database, and built a `Post` struct, based on its `:posts` association, with the `user_id` foreign key field properly set to the ID in the `User` struct.

## Many-to-many

### Prep

Let's assume we have two schemas: `Post` and `Tag`. The `Post` schema was defined in the previous section and the `Tag` schema will be defined now.

Let's start with the tag migration:

```
mix ecto.gen.migration create_tag
```

with the following columns:

```elixir
# priv/repo/migrations/*create_tag.exs
defmodule EctoAssoc.Repo.Migrations.CreateTag do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add :name, :string
    end
  end
end
```

and the following schema:

```elixir
defmodule EctoAssoc.Tag do
  use Ecto.Schema

  schema "tags" do
    field :name, :string
  end
end
```

### Adding Associations

Now we want to associate the post with the tags and vice-versa:

 * one post can have many tags
 * one tag can have many posts

This is a `many-to-many` relationship. Notice both sides can have many entries. In the previous sections we put the foreign key on the side that "belongs to" the other, which is not available here.

One way to handle `many-to-many` relationships is to introduce an additional table which explicitly tracks the tag-post relationship by pointing to both tags and posts entries.

So let's do that:

```
mix ecto.gen.migration create_posts_tags
```

with the following contents:

```elixir
# priv/repo/migrations/*_create_posts_tags
defmodule EctoAssoc.Repo.Migrations.CreatePostsTags do
  use Ecto.Migration

  def change do
    create table(:posts_tags) do
      add :tag_id, references(:tags)
      add :post_id, references(:posts)
    end

    create unique_index(:posts_tags, [:tag_id, :post_id])
  end
end
```

On the DB level, this creates a new table `posts_tags` with two columns that point at the `tag_id` and `post_id`. We also create a unique index, such that the association is always unique.

For the `Post` we use the [`many_to_many`](Ecto.Schema.html#many_to_many/3) macro to associate the `Tag` through the
new `posts_tags` table.

```elixir
# lib/ecto_assoc/post.ex
defmodule EctoAssoc.Post do
  use Ecto.Schema

  schema "posts" do
    field :header, :string
    field :body, :string
    # the following line was added
    many_to_many :tags, EctoAssoc.Tag, join_through: "posts_tags"
  end
end
```

For the `Tag` we do the same. We use the `many_to_many` macro to associate the `Post` through the
new `posts_tags` schema:

```elixir
# lib/ecto_assoc/tag.ex
defmodule EctoAssoc.Tag do
  use Ecto.Schema

  schema "tags" do
    field :name, :string
    # the following line was added
    many_to_many :posts, EctoAssoc.Post, join_through: "posts_tags"
  end
end
```

### Persistence

Let's create some tags:

```elixir
iex> clickbait_tag = Repo.insert! %Tag{name: "clickbait"}
%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 1,
 name: "clickbait",
 posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}

iex> misc_tag = Repo.insert! %Tag{name: "misc"}
%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 2,
 name: "misc",
 posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}

iex> ecto_tag = Repo.insert! %Tag{name: "ecto"}
%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 3,
 name: "ecto",
 posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}
```

And let's create a post:

```elixir
iex> post = %Post{header: "Clickbait header", body: "No real content"}
...> post = Repo.insert!(post)
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
 body: "No real content", header: "Clickbait header", id: 1,
 tags: #Ecto.Association.NotLoaded<association :tags is not loaded>}
```

Ok, but tag and post are not associated, yet. We might expect, as done in `one-to-one`, to create either a post or a tag with the associated entries and insert them all at once. However, notice we cannot use `Ecto.build_assoc/3`, since the foreign key does not belong to the `Post` nor the `Tag` struct.

Another option is to use Ecto changesets, which provide many conveniences for dealing with *changes*. For example:

```elixir
iex> post_changeset = Ecto.Changeset.change(post)
iex> post_with_tags = Ecto.Changeset.put_assoc(post_changeset, :tags, [clickbait_tag, misc_tag])
iex> post = Repo.update!(post_with_tags)
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
 body: "No real content", header: "Clickbait header", id: 1,
 tags: [%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 1,
   name: "clickbait",
   posts: #Ecto.Association.NotLoaded<association :posts is not loaded>},
  %EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 2,
   name: "misc",
   posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}]}
```

Let's examine the post:

```elixir
iex> post = Repo.get(Post, post.id) |> Repo.preload(:tags)
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
 body: "No real content", header: "Clickbait header", id: 1,
 tags: [%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 1,
   name: "clickbait",
   posts: #Ecto.Association.NotLoaded<association :posts is not loaded>},
  %EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 2,
   name: "misc",
   posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}]}

iex> post.header
"Clickbait header"

iex> post.body
"No real content"

iex> post.tags
[%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 1,
  name: "clickbait",
  posts: #Ecto.Association.NotLoaded<association :posts is not loaded>},
 %EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 2,
  name: "misc",
  posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}]

iex> Enum.map(post.tags, & &1.name)
["clickbait", "misc"]
```

The association also works in the other direction:

```elixir
iex> tag = Repo.get(Tag, 1) |> Repo.preload(:posts)
%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 1,
 name: "clickbait",
 posts: [%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
   body: "No real content", header: "Clickbait header", id: 1,
   tags: #Ecto.Association.NotLoaded<association :tags is not loaded>}]}
```

The advantage of using [`Ecto.Changeset`](Ecto.Changeset.html) is that it is responsible for tracking the changes between your data structures and the associated data. For example, if you want to remove the "clickbait" tag from the post, one way to do so is by calling [`Ecto.Changeset.put_assoc/3`](Ecto.Changeset.html#put_assoc/4) once more but without the "clickbait" tag.  This will not work right now, because the `:on_replace` option for the `many_to_many` relationship defaults to `:raise`.  Go ahead and try it.  When you try to call `put_assoc`, a runtime error will be raised:

```elixir
iex> post_changeset = Ecto.Changeset.change(post)
iex> post_with_tags = Ecto.Changeset.put_assoc(post_changeset, :tags, [misc_tag])
** (RuntimeError) you are attempting to change relation :tags of
EctoAssoc.Post but the `:on_replace` option of
this relation is set to `:raise`.

By default it is not possible to replace or delete embeds and
associations during `cast`. Therefore Ecto requires all existing
data to be given on update. Failing to do so results in this
error message.

If you want to replace data or automatically delete any data
not sent to `cast`, please set the appropriate `:on_replace`
option when defining the relation. The docs for `Ecto.Changeset`
covers the supported options in the "Associations, embeds and on
replace" section.

However, if you don't want to allow data to be replaced or
deleted, only updated, make sure that:

  * If you are attempting to update an existing entry, you
    are including the entry primary key (ID) in the data.

  * If you have a relationship with many children, at least
    the same N children must be given on update.
...
```

You should carefully read the documentation for [`Ecto.Schema.many_to_many/3`](Ecto.Schema.html#many_to_many/3). It makes sense in this case that we want to delete relationships in the join table `posts_tags` when updating a post with new tags.  Here we want to drop the tag "clickbait" and just keep the tag "misc", so we really do want the relationship in the joining table to be removed.  To do that, change the definition of the `many_to_many/3` in the `Post` schema:

```elixir
# lib/ecto_assoc/post.ex
defmodule EctoAssoc.Post do
  use Ecto.Schema

  schema "posts" do
    field :header, :string
    field :body, :string
    # the following line was edited to change the on_replace option from its default value of :raise
    many_to_many :tags, EctoAssoc.Tag, join_through: "posts_tags", on_replace: :delete
  end
end
```

On the other hand, it probably *doesn't* make much sense to be able to remove relationships from the other end.  That is, with just a tag, it is hard to decide if a post should be related to the tag or not.  So it makes sense that we should still raise an error if we try to change posts that are related to tags from the tag side of things.

With the `:on_replace` option changed, Ecto will compare the data you gave with the tags currently in the post and conclude the association between the post and the "clickbait" tag must be removed, as follows:

```elixir
iex> post_changeset = Ecto.Changeset.change(post)
iex> post_with_tags = Ecto.Changeset.put_assoc(post_changeset, :tags, [misc_tag])
iex> post = Repo.update!(post_with_tags)
```

## References

  * [Ecto.Schema.belongs_to](https://hexdocs.pm/ecto/Ecto.Schema.html#belongs_to/3)
  * [Ecto.Schema.has_one](https://hexdocs.pm/ecto/Ecto.Schema.html#has_one/3)
  * [Ecto.Schema.has_many](https://hexdocs.pm/ecto/Ecto.Schema.html#has_many/3)
  * [Ecto.Schema.many_to_many](https://hexdocs.pm/ecto/Ecto.Schema.html#many_to_many/3)
  * [Ecto.build_assoc](https://hexdocs.pm/ecto/Ecto.html#build_assoc/3)
  * [Ecto.Changeset.put_assoc](https://hexdocs.pm/ecto/Ecto.Changeset.html#put_assoc/4)
