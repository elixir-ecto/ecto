# Ecto Association Guide
This guide assumes you worked through the "getting started" guide and want to learn more about associations.

With ecto (like every other DB layer) you can associate schemas with other schemas.

There are three kinds of associations
- one-to-one,
- one-to-many,and
- many-to-many.

In this tutorial we're going to create a minimal ecto project
(similar to the getting started guide),
then we're going to create basic schemas and migrations,
and finally associate the schemas.


## Ecto Setup
First, we're going to create a basic ecto project which is going to be used for
the rest of the tutorial.
Note, the steps are taken from the getting started guide.
You can also clone the project from TODO.

Let's create a new project.
```
$ mix new ecto_assoc --sup
```

Add `ecto` and `postgrex` as dependencies to `mix.exs` and add them to our
application:
```elixir
# mix.exs
# ...
def application do
  [applications: [:logger, :ecto, :postgrex],
   mod: {EctoAssoc, []}]
end

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

Add the repo to the supervision tree:
```elixir
  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    children = [
      worker(EctoAssoc.Repo, [])
    ]
    ...
```

Finally let's create the DB:
```
$ mix ecto.create
$ iex -S mix
```

## One-to-one
### Prep
Let's assume we have two schemas: User and Avatar.

The schemas and corresponding migrations look like this:
```elixir
# create a migration: mix ecto.gen.migration create_user
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

```elixir
# create a migration: mix ecto.gen.migration create_avatar
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
Now we want to associate the user with the avatar and vice versa:
- one user has one avatar
- one avatar belongs to one user

For the *avatar* we create a migration that adds a `user_id` reference.
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
This adds a `user_id` column to the DB which refecences an entry in the users table.

For the *avatar* we add a `belongs_to` field to the schema
```elixir
defmodule EctoAssoc.Avatar do
  schema "avatars" do
    field :nick_name, :string
    field :pic_url, :string
    belongs_to :user, EctoAssoc.User  # this was added
  end
end
```
`belongs_to` is a macro which uses a foreign key (in this case `user_id`) to make the associated schema accessible through the avatar, i.e., you can access the user via `avatar.user`.

For the *user* we add a `has_one` field to the schema
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
`has_one` does not add anything to the DB.
The foreign key of the associated schema, `Avatar`, is used to make the avatar available from the user, i.e., you can access the avatar via `user.avatar`.

### Persistence
Now let's add data to the DB.
Start iex:
```
$ iex -S mix
```

For convenience we alias some modules:
```elixir
iex(1)> alias EctoAssoc.Repo
EctoAssoc.Repo
iex(2)> alias EctoAssoc.User
EctoAssoc.User
iex(3)> alias EctoAssoc.Avatar
EctoAssoc.Avatar
```

Create a user changeset and insert it into the repo:
```elixir
iex(5)> user_cs = %User{} |> Ecto.Changeset.cast(%{name: "John Doe", email: "johan@example.com"}, [:name, :email])
#Ecto.Changeset<action: nil,
 changes: %{email: "johan@example.com", name: "John Doe"}, errors: [],
 data: #EctoAssoc.User<>, valid?: true>

iex(6)> user = Repo.insert!(user_cs)
%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
 avatar: #Ecto.Association.NotLoaded<association :avatar is not loaded>,
 email: "johan@example.com", id: 3, name: "John Doe"}
```

This time let's add another user with an avatar association. We use `Ecto.Changeset.put_assoc` for this.
```elixir
iex(7)> user_cs = %User{} |> Ecto.Changeset.cast(%{name: "Jane Doe", email: "jane@example.com"}, [:name, :email]) |> Ecto.Changeset.put_assoc(:avatar, %{nick_name: "EctOr", pick_url: "http://elixir-lang.org/images/logo/logo.png"})
#Ecto.Changeset<action: nil,
 changes: %{avatar: #Ecto.Changeset<action: :insert,
    changes: %{nick_name: "EctOr",
      pick_url: "http://elixir-lang.org/images/logo/logo.png"}, errors: [],
    data: #EctoAssoc.Avatar<>, valid?: true>, email: "jane@example.com",
   name: "Jane Doe"}, errors: [], data: #EctoAssoc.User<>, valid?: true>

iex(8)> user = Repo.insert!(user_cs)
%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
 avatar: %{__meta__: #Ecto.Schema.Metadata<:loaded, "avatars">,
   __struct__: EctoAssoc.Avatar, id: 2, nick_name: "EctOr", pic_url: nil,
   pick_url: "http://elixir-lang.org/images/logo/logo.png",
   user: #Ecto.Association.NotLoaded<association :user is not loaded>,
   user_id: 4}, email: "jane@example.com", id: 4, name: "Jane Doe"}
```

Let's verify that it works by retrieving all Users and their associated avatars:
```elixir
iex(9)> Repo.all(User) |> Repo.preload(:avatar)
[%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">, avatar: nil,
  email: "johan@example.com", id: 3, name: "John Doe"},
 %EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
  avatar: %EctoAssoc.Avatar{__meta__: #Ecto.Schema.Metadata<:loaded, "avatars">,
   id: 2, nick_name: "EctOr", pic_url: nil,
   user: #Ecto.Association.NotLoaded<association :user is not loaded>,
   user_id: 4}, email: "jane@example.com", id: 4, name: "Jane Doe"}]
```


## Many-to-one
### Prep
Let's assume we have two schemas: `User` and `Post`.

The schamas and corresponding migrations look like this:
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

```elixir
# create a migration: mix ecto.gen.migration create_user
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

```elixir
# create a migration: mix ecto.gen.migration create_post
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


### Adding Associations
Now we want to associate the user with the post and vice versa:
- one user has many post
- one post belongs to one user

For the *post* we
- create a migration that adds the `user_id` reference
- add a `belongs_to` field to the schema

TODO add listing

For the *user* we
- add a `has_many` field to the schema

TODO add listing

### Persistence
```elixir
iex(1)> alias EctoAssoc.Repo
EctoAssoc.Repo

iex(2)> alias EctoAssoc.User
EctoAssoc.User

iex(3)> alias EctoAssoc.Post
EctoAssoc.Post
```

```
iex(6)> user_cs = %User{} |> Ecto.Changeset.cast(%{name: "John Doe", email: "johan@example.com"}, [:name, :email])
#Ecto.Changeset<action: nil,
 changes: %{email: "johan@example.com", name: "John Doe"}, errors: [],
 data: #EctoAssoc.User<>, valid?: true>

iex(7)> user = Repo.insert!(user_cs)
14:33:35.513 [debug] QUERY OK db=0.3ms queue=0.1ms
begin []
14:33:35.534 [debug] QUERY OK db=4.6ms
INSERT INTO "users" ("email","name") VALUES ($1,$2) RETURNING "id" ["johan@example.com", "John Doe"]
14:33:35.535 [debug] QUERY OK db=1.2ms
commit []
%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
 email: "johan@example.com", id: 1, name: "John Doe",
 posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}
```

```
iex(6)> post_cs = Ecto.build_assoc(user, :posts, %{header: "Clickbait header", body: "No real content"})
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:built, "posts">,
 body: "No real content", header: "Clickbait header", id: nil,
 user: #Ecto.Association.NotLoaded<association :user is not loaded>, user_id: 1}

iex(7)> post = Repo.insert!(post_cs)
14:54:28.193 [debug] QUERY OK db=0.3ms
begin []
14:54:28.197 [debug] QUERY OK db=2.9ms
INSERT INTO "posts" ("body","header","user_id") VALUES ($1,$2,$3) RETURNING "id" ["No real content", "Clickbait header", 1]
14:54:28.199 [debug] QUERY OK db=2.6ms
commit []
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
 body: "No real content", header: "Clickbait header", id: 1,
 user: #Ecto.Association.NotLoaded<association :user is not loaded>, user_id: 1}
```

Let's add another one.
```
iex(8)> post = Ecto.build_assoc(user, :posts, %{header: "5 ways to improve your Ecto", body: "TODO add url of this tutorial"}) |> Repo.insert!()
14:56:45.571 [debug] QUERY OK db=0.4ms queue=0.1ms
begin []
14:56:45.573 [debug] QUERY OK db=2.2ms
INSERT INTO "posts" ("body","header","user_id") VALUES ($1,$2,$3) RETURNING "id" ["TODO add url of this tutorial", "5 ways to improve your Ecto", 1]
14:56:45.576 [debug] QUERY OK db=2.7ms
commit []
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
 body: "TODO add url of this tutorial", header: "5 ways to improve your Ecto",
 id: 2, user: #Ecto.Association.NotLoaded<association :user is not loaded>,
 user_id: 1}
```

Let's see if it worked
```
iex(11)> Repo.get(User, user.id) |> Repo.preload(:posts)

14:58:17.170 [debug] QUERY OK source="users" db=2.0ms
SELECT u0."id", u0."name", u0."email" FROM "users" AS u0 WHERE (u0."id" = $1) [1]

14:58:17.173 [debug] QUERY OK source="posts" db=2.2ms queue=0.2ms
SELECT p0."id", p0."header", p0."body", p0."user_id", p0."user_id" FROM "posts" AS p0 WHERE (p0."user_id" = $1) ORDER BY p0."user_id" [1]
%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
 email: "johan@example.com", id: 1, name: "John Doe",
 posts: [%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
   body: "No real content", header: "Clickbait header", id: 1,
   user: #Ecto.Association.NotLoaded<association :user is not loaded>,
   user_id: 1},
  %EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
   body: "TODO add url of this tutorial", header: "5 ways to improve your Ecto",
   id: 2, user: #Ecto.Association.NotLoaded<association :user is not loaded>,
   user_id: 1}]}
```

## Many-to-many
### Prep
Let's assume we have two schemas: Post and Tag.

The schemas and their migration look like this:

TODO add listing

### Adding Associations
Now we want to associate the post with the tags and vice versa:
- one post can have many tags
- one tag can belong to many post
This is a many-to-many relationship.

One way to handle many-to-many relationships is to introduce an additional schema which explicitly tracks the tag-post relationship.
So let's do that:

➤ mix ecto.gen.migration create_tag_post_association

For the *post* we
- add the many_to_many macro the schema

TODO add listing

For the *tag* we
- add the many_to_many macro the schema

TODO add listing

### Persistence
Let's create some tags
#+BEGIN_SRC iex
iex(14)> clickbait_tag = %Tag{} |> Ecto.Changeset.cast(%{name: "clickbait"}, [:name]) |> Repo.insert!()

16:06:08.547 [debug] QUERY OK db=0.2ms
begin []

16:06:08.549 [debug] QUERY OK db=1.5ms
INSERT INTO "tags" ("name") VALUES ($1) RETURNING "id" ["clickbait"]

16:06:08.554 [debug] QUERY OK db=4.7ms
commit []
%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 1,
 name: "clickbait",
 posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}
iex(15)> misc_tag = %Tag{} |> Ecto.Changeset.cast(%{name: "misc"}, [:name]) |> Repo.insert!()

16:06:23.307 [debug] QUERY OK db=0.2ms
begin []

16:06:23.309 [debug] QUERY OK db=2.1ms
INSERT INTO "tags" ("name") VALUES ($1) RETURNING "id" ["misc"]

16:06:23.312 [debug] QUERY OK db=2.8ms
commit []
%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 2,
 name: "misc",
 posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}
iex(16)> ecto_tag = %Tag{} |> Ecto.Changeset.cast(%{name: "ecto"}, [:name]) |> Repo.insert!()

16:06:40.548 [debug] QUERY OK db=0.4ms queue=0.1ms
begin []

16:06:40.551 [debug] QUERY OK db=2.0ms
INSERT INTO "tags" ("name") VALUES ($1) RETURNING "id" ["ecto"]

16:06:40.553 [debug] QUERY OK db=2.7ms
commit []
%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 3,
 name: "ecto",
 posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}
```

And let's create a post
```
iex(5)> post = %Post{} |> Ecto.Changeset.cast(%{header: "Clickbait header", body: "No real content"}, [:header, :body]) |> Repo.insert!()

16:04:19.158 [debug] QUERY OK db=0.2ms
begin []

16:04:19.171 [debug] QUERY OK db=1.3ms
INSERT INTO "posts" ("body","header") VALUES ($1,$2) RETURNING "id" ["No real content", "Clickbait header"]

16:04:19.172 [debug] QUERY OK db=1.2ms
commit []
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
 body: "No real content", header: "Clickbait header", id: 1,
 tags: #Ecto.Association.NotLoaded<association :tags is not loaded>}

```

Ok, but tag and post are not associated.
```
Repo.insert!(%TagPostAssociation{post: post, tag: clickbait_misc})
Repo.insert!(%TagPostAssociation{post: post, tag: clickbait_misc})
```

```
iex(17)> Repo.insert!(%EctoAssoc.TagPostAssociation{post: post, tag: clickbait_tag})

16:07:37.558 [debug] QUERY OK db=0.5ms queue=0.1ms
begin []

16:07:37.570 [debug] QUERY OK db=3.6ms
INSERT INTO "tag_post_associations" ("post_id","tag_id") VALUES ($1,$2) RETURNING "id" [1, 1]

16:07:37.573 [debug] QUERY OK db=2.7ms
commit []
%EctoAssoc.TagPostAssociation{__meta__: #Ecto.Schema.Metadata<:loaded, "tag_post_associations">,
 id: 1,
 post: %EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
  body: "No real content", header: "Clickbait header", id: 1,
  tags: #Ecto.Association.NotLoaded<association :tags is not loaded>},
 post_id: 1,
 tag: %EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 1,
  name: "clickbait",
  posts: #Ecto.Association.NotLoaded<association :posts is not loaded>},
 tag_id: 1}
iex(18)> Repo.insert!(%EctoAssoc.TagPostAssociation{post: post, tag: misc_tag})

16:07:44.472 [debug] QUERY OK db=0.4ms queue=0.1ms
begin []

16:07:44.478 [debug] QUERY OK db=5.6ms
INSERT INTO "tag_post_associations" ("post_id","tag_id") VALUES ($1,$2) RETURNING "id" [1, 2]

16:07:44.481 [debug] QUERY OK db=3.0ms
commit []
%EctoAssoc.TagPostAssociation{__meta__: #Ecto.Schema.Metadata<:loaded, "tag_post_associations">,
 id: 2,
 post: %EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
  body: "No real content", header: "Clickbait header", id: 1,
  tags: #Ecto.Association.NotLoaded<association :tags is not loaded>},
 post_id: 1,
 tag: %EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 2,
  name: "misc",
  posts: #Ecto.Association.NotLoaded<association :posts is not loaded>},
 tag_id: 2}
```

Let's examin the the post
```
iex(21)> post = Repo.get(Post, 1) |> Repo.preload(:tags)

16:09:28.129 [debug] QUERY OK source="posts" db=2.4ms
SELECT p0."id", p0."header", p0."body" FROM "posts" AS p0 WHERE (p0."id" = $1) [1]

16:09:28.133 [debug] QUERY OK source="tags" db=3.4ms queue=0.2ms
SELECT t0."id", t0."name", p1."id" FROM "tags" AS t0 INNER JOIN "posts" AS p1 ON p1."id" = ANY($1) INNER JOIN "tag_post_associations" AS t2 ON t2."post_id" = p1."id" WHERE (t2."tag_id" = t0."id") ORDER BY p1."id" [[1]]
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
 body: "No real content", header: "Clickbait header", id: 1,
 tags: [%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 1,
   name: "clickbait",
   posts: #Ecto.Association.NotLoaded<association :posts is not loaded>},
  %EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 2,
   name: "misc",
   posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}]}

iex(48)> post.header
"Clickbait header"
iex(49)> post.body
"No real content"
iex(50)> post.tags
[%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 1,
  name: "clickbait",
  posts: #Ecto.Association.NotLoaded<association :posts is not loaded>},
 %EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 2,
  name: "misc",
  posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}]
iex(51)> Enum.at(post.tags, 0).name
"clickbait"
iex(52)> Enum.at(post.tags, 1).name
"misc"
```

And the association also work in the other direction
```
iex(59)> tag = Repo.get(Tag, 1) |> Repo.preload(:posts)

16:20:57.790 [debug] QUERY OK source="tags" db=1.4ms
SELECT t0."id", t0."name" FROM "tags" AS t0 WHERE (t0."id" = $1) [1]

16:20:57.792 [debug] QUERY OK source="posts" db=1.7ms queue=0.1ms
SELECT p0."id", p0."header", p0."body", t1."id" FROM "posts" AS p0 INNER JOIN "tags" AS t1 ON t1."id" = ANY($1) INNER JOIN "tag_post_associations" AS t2 ON t2."tag_id" = t1."id" WHERE (t2."post_id" = p0."id") ORDER BY t1."id" [[1]]
%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 1,
 name: "clickbait",
 posts: [%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
   body: "No real content", header: "Clickbait header", id: 1,
   tags: #Ecto.Association.NotLoaded<association :tags is not loaded>}]}
```

## Next steps
TODO Read about
- `put_assoc`
- `build_assoc`

- `belongs_to`
- `has_one`
- `has_many`
- `many_to_many`
