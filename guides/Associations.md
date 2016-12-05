# Ecto Association Guide
This guide assumes you worked through the "getting started" guide and want to learn more about associations.

With ecto (like every other DB layer) you can associate schemas with other schemas.

There are three kinds of associations:
- one-to-one
- one-to-many
- many-to-many

In this tutorial we're going to create a minimal ecto project
(similar to the getting started guide),
then we're going to create basic schemas and migrations,
and finally associate the schemas.


## Ecto Setup
First, we're going to create a basic ecto project which is going to be used for
the rest of the tutorial.
Note, the steps are taken from the getting started guide.
You can also clone the project from (TODO add link to project).

Let's create a new project.
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

Also add them to our application:
```elixir
# mix.exs
def application do
  [applications: [:logger, :ecto, :postgrex],
   mod: {EctoAssoc, []}]
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

For the *avatar* we create a migration that adds a `user_id` reference:
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

For the *avatar* we add a `belongs_to` field to the schema:
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
iex> alias EctoAssoc.Repo
EctoAssoc.Repo

iex> alias EctoAssoc.User
EctoAssoc.User

iex> alias EctoAssoc.Avatar
EctoAssoc.Avatar
```

Create a user changeset and insert it into the repo:
```elixir
iex> user_cs =
...>   %User{}
...>   |> Ecto.Changeset.cast(%{name: "John Doe", email: "johan@example.com"}, [:name, :email])
#Ecto.Changeset<action: nil,
 changes: %{email: "johan@example.com", name: "John Doe"}, errors: [],
 data: #EctoAssoc.User<>, valid?: true>

iex> user = Repo.insert!(user_cs)
%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
 avatar: #Ecto.Association.NotLoaded<association :avatar is not loaded>,
 email: "johan@example.com", id: 3, name: "John Doe"}
```

This time let's add another user with an avatar association. We use `Ecto.Changeset.put_assoc` for this.
```elixir
iex> user_cs =
...>   %User{}
...>   |> Ecto.Changeset.cast(%{name: "Jane Doe", email: "jane@example.com"}, [:name, :email])
...>   |> Ecto.Changeset.put_assoc(:avatar, %{nick_name: "EctOr", pick_url: "http://elixir-lang.org/images/logo/logo.png"})
#Ecto.Changeset<action: nil,
 changes: %{avatar: #Ecto.Changeset<action: :insert,
    changes: %{nick_name: "EctOr",
      pick_url: "http://elixir-lang.org/images/logo/logo.png"}, errors: [],
    data: #EctoAssoc.Avatar<>, valid?: true>, email: "jane@example.com",
   name: "Jane Doe"}, errors: [], data: #EctoAssoc.User<>, valid?: true>

iex> user = Repo.insert!(user_cs)
%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
 avatar: %{__meta__: #Ecto.Schema.Metadata<:loaded, "avatars">,
   __struct__: EctoAssoc.Avatar, id: 2, nick_name: "EctOr", pic_url: nil,
   pick_url: "http://elixir-lang.org/images/logo/logo.png",
   user: #Ecto.Association.NotLoaded<association :user is not loaded>,
   user_id: 4}, email: "jane@example.com", id: 4, name: "Jane Doe"}
```

Let's verify that it works by retrieving all Users and their associated avatars:
```elixir
iex> Repo.all(User) |> Repo.preload(:avatar)
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
Now we want to associate the user with the post and vice versa:
- one user has many posts
- one post belongs to one user

For the *post* we create a migration that adds a `user_id` reference:
```elixir
# mix ecto.gen.migration post_belongs_to_user
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

For the *post* we add a `belongs_to` field to the schema:
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
`belongs_to` is a macro which uses a foreign key (in this case `user_id`) to make the associated schema accessible through the post,
i.e., you can access the user via `post.user`.

For the *user* we add a `has_many` field to the schema:
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
`has_many` does not add anything to the DB.
The foreign key of the associated schema, `Post`, is used to make the posts available from the user,
i.e., you can access the posts via `user.posts`.


### Persistence
Start iex:
```
$ iex -S mix
```

For convenience we alias some modules:
```elixir
iex> alias EctoAssoc.Repo
EctoAssoc.Repo

iex> alias EctoAssoc.User
EctoAssoc.User

iex> alias EctoAssoc.Post
EctoAssoc.Post
```

Let's create a User and store it in the DB:
```elixir
iex> user_cs =
...>   %User{}
...>   |> Ecto.Changeset.cast(%{name: "John Doe", email: "johan@example.com"}, [:name, :email])
#Ecto.Changeset<action: nil,
 changes: %{email: "johan@example.com", name: "John Doe"}, errors: [],
 data: #EctoAssoc.User<>, valid?: true>

iex> user = Repo.insert!(user_cs)
%EctoAssoc.User{__meta__: #Ecto.Schema.Metadata<:loaded, "users">,
 email: "johan@example.com", id: 1, name: "John Doe",
 posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}
```

Let's build an associated post and store it in the DB:
```elixir
iex> post_cs = Ecto.build_assoc(user, :posts, %{header: "Clickbait header", body: "No real content"})
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:built, "posts">,
 body: "No real content", header: "Clickbait header", id: nil,
 user: #Ecto.Association.NotLoaded<association :user is not loaded>, user_id: 1}

iex> post = Repo.insert!(post_cs)
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
 body: "No real content", header: "Clickbait header", id: 1,
 user: #Ecto.Association.NotLoaded<association :user is not loaded>, user_id: 1}
```

Let's add another post to the user:
```elixir
iex> post =
...>   Ecto.build_assoc(user, :posts, %{header: "5 ways to improve your Ecto", body: "TODO add url of this tutorial"})
...>   |> Repo.insert!()
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
 body: "TODO add url of this tutorial", header: "5 ways to improve your Ecto",
 id: 2, user: #Ecto.Association.NotLoaded<association :user is not loaded>,
 user_id: 1}
```

Let's see if it worked:
```
iex> Repo.get(User, user.id) |> Repo.preload(:posts)
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

TODO explain `build_assoc`


## Many-to-many
### Prep
Let's assume we have two schemas: Post and Tag.

The schemas and their migration look like this:
```elixir
# mix ecto.gen.migration create_post
# priv/repo/migrations/*create_post.exs
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
# mix ecto.gen.migration create_tag
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

```elixir
defmodule EctoAssoc.Tag do
  use Ecto.Schema

  schema "tags" do
    field :name, :string
  end
end
```


### Adding Associations
Now we want to associate the post with the tags and vice versa:
- one post can have many tags
- one tag can belong to many posts.

This is a `many-to-many` relationship.

One way to handle `many-to-many` relationships is to introduce an additional schema which explicitly tracks the tag-post relationship.
So let's do that:

```elixir
# $ mix ecto.gen.migration create_tag_post_association
# priv/repo/migrations/*_create_tag_post_association
defmodule EctoAssoc.Repo.Migrations.CreateTagPostAssociation do
  use Ecto.Migration

  def change do
    create table(:tag_post_associations) do
      add :tag_id, references(:tags)
      add :post_id, references(:posts)
      # Note you can add additional data to the association schema, like:
      # timestamps()
    end

    create unique_index(:tag_post_associations, [:tag_id, :post_id])
  end
end
```
On the DB level, this creates a new table `tag_post_associations` with two
colums that point at the `tag_id` and `post_id`.
We also create a unique index, such that the association is always unique.

For the *post* we use the `many_to_many` macro to associate the `Tag` through the
new `TagPostAssociation` schema.

```elixir
# lib/ecto_assoc/post.ex
defmodule EctoAssoc.Post do
  use Ecto.Schema

  schema "posts" do
    field :header, :string
    field :body, :string
    # the following line was added
    many_to_many :tags, EctoAssoc.Tag, join_through: EctoAssoc.TagPostAssociation
  end
end
```

For the *post* we do the same.
We use the `many_to_many` macro to associate the `Post` through the
new `TagPostAssociation` schema.
```elixir
# lib/ecto_assoc/tag.ex
defmodule EctoAssoc.Tag do
  use Ecto.Schema

  schema "tags" do
    field :name, :string
    # the following line was added
    many_to_many :posts, EctoAssoc.Post, join_through: EctoAssoc.TagPostAssociation
  end
end
```

### Persistence
Let's create some tags:
```elixir
iex> clickbait_tag = %Tag{} |> Ecto.Changeset.cast(%{name: "clickbait"}, [:name]) |> Repo.insert!()
%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 1,
 name: "clickbait",
 posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}

iex> misc_tag = %Tag{} |> Ecto.Changeset.cast(%{name: "misc"}, [:name]) |> Repo.insert!()
%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 2,
 name: "misc",
 posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}

iex> ecto_tag = %Tag{} |> Ecto.Changeset.cast(%{name: "ecto"}, [:name]) |> Repo.insert!()
%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 3,
 name: "ecto",
 posts: #Ecto.Association.NotLoaded<association :posts is not loaded>}
```

And let's create a post:
```elixir
iex> post =
...>   %Post{}
...>   |> Ecto.Changeset.cast(%{header: "Clickbait header", body: "No real content"}, [:header, :body])
...>   |> Repo.insert!()
%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
 body: "No real content", header: "Clickbait header", id: 1,
 tags: #Ecto.Association.NotLoaded<association :tags is not loaded>}
```

Ok, but tag and post are not associated, yet.
We can create an association through the `TagPostAssociation` directly:
```elixir
iex> Repo.insert!(%EctoAssoc.TagPostAssociation{post: post, tag: clickbait_tag})
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

iex> Repo.insert!(%EctoAssoc.TagPostAssociation{post: post, tag: misc_tag})
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

Let's examine the post
```elixir
iex> post = Repo.get(Post, 1) |> Repo.preload(:tags)
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

iex> Enum.at(post.tags, 0).name
"clickbait"

iex> Enum.at(post.tags, 1).name
"misc"
```

Of course, the associations also work in the other direction:
```elixir
iex> tag = Repo.get(Tag, 1) |> Repo.preload(:posts)
%EctoAssoc.Tag{__meta__: #Ecto.Schema.Metadata<:loaded, "tags">, id: 1,
 name: "clickbait",
 posts: [%EctoAssoc.Post{__meta__: #Ecto.Schema.Metadata<:loaded, "posts">,
   body: "No real content", header: "Clickbait header", id: 1,
   tags: #Ecto.Association.NotLoaded<association :tags is not loaded>}]}
```

## References
- [belongs_to](https://hexdocs.pm/ecto/Ecto.Schema.html#belongs_to/3)
- [has_one](https://hexdocs.pm/ecto/Ecto.Schema.html#has_one/3)
- [has_many](https://hexdocs.pm/ecto/Ecto.Schema.html#has_many/3)
- [many_to_many](https://hexdocs.pm/ecto/Ecto.Schema.html#many_to_many/3)
- [put_assoc](https://hexdocs.pm/ecto/Ecto.Changeset.html#put_assoc/4)
- [build_assoc](https://hexdocs.pm/ecto/Ecto.html#build_assoc/3)
