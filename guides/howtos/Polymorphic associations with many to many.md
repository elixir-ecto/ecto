# Polymorphic associations with many to many

Besides `belongs_to`, `has_many`, `has_one` and `:through` associations, Ecto also includes `many_to_many`. `many_to_many` relationships, as the name says, allows a record from table X to have many associated entries from table Y and vice-versa. Although `many_to_many` associations can be written as `has_many :through`, using `many_to_many` may considerably simplify some workflows.

In this guide, we will talk about polymorphic associations and how `many_to_many` can remove boilerplate from certain approaches compared to `has_many :through`.

## Todo lists v65131

The internet has seen its share of todo list applications. But that won't stop us from creating our own!

In our case, there is one aspect of todo list applications we are interested in, which is the relationship where the todo list has many todo items. This exact scenario is explored in detail in a post about [nested associations and embeds](https://dashbit.co/blog/working-with-ecto-associations-and-embeds) from Dashbit's blog. Let's recap the important points.

Our todo list app has two schemas, `Todo.List` and `Todo.Item`:

```elixir
defmodule MyApp.TodoList do
  use Ecto.Schema

  schema "todo_lists" do
    field :title
    has_many :todo_items, MyApp.TodoItem
    timestamps()
  end
end

defmodule MyApp.TodoItem do
  use Ecto.Schema

  schema "todo_items" do
    field :description
    timestamps()
  end
end
```

One of the ways to introduce a todo list with multiple items into the database is to couple our UI representation to our schemas. That's the approach we took in the blog post with Phoenix. Roughly:

```eex
<%= form_for @todo_list_changeset,
             todo_list_path(@conn, :create),
             fn f -> %>
  <%= text_input f, :title %>
  <%= inputs_for f, :todo_items, fn i -> %>
    ...
  <% end %>
<% end %>
```

When such a form is submitted in Phoenix, it will send parameters with the following shape:

```elixir
%{
  "todo_list" => %{
    "title" => "shopping list",
    "todo_items" => %{
      0 => %{"description" => "bread"},
      1 => %{"description" => "eggs"}
    }
  }
}
```

We could then retrieve those parameters and pass it to an Ecto changeset and Ecto would automatically figure out what to do:

```elixir
# In MyApp.TodoList
def changeset(struct, params \\ %{}) do
  struct
  |> Ecto.Changeset.cast(params, [:title])
  |> Ecto.Changeset.cast_assoc(:todo_items, required: true)
end

# And then in MyApp.TodoItem
def changeset(struct, params \\ %{}) do
  struct
  |> Ecto.Changeset.cast(params, [:description])
end
```

By calling `Ecto.Changeset.cast_assoc/3`, Ecto will look for a "todo_items" key inside the parameters given on cast, and compare those parameters with the items stored in the todo list struct. Ecto will automatically generate instructions to insert, update or delete todo items such that:

  * if a todo item sent as parameter has an ID and it matches an existing associated todo item, we consider that todo item should be updated
  * if a todo item sent as parameter does not have an ID (nor a matching ID), we consider that todo item should be inserted
  * if a todo item is currently associated but its ID was not sent as parameter, we consider the todo item is being replaced and we act according to the `:on_replace` callback. By default `:on_replace` will raise so you choose a behaviour between replacing, deleting, ignoring or nilifying the association

The advantage of using `cast_assoc/3` is that Ecto is able to do all of the hard work of keeping the entries associated, **as long as we pass the data exactly in the format that Ecto expects**. However, such approach is not always preferable and in many situations it is better to design our associations differently or decouple our UIs from our database representation.

## Polymorphic todo items

To show an example of where using `cast_assoc/3` is just too complicated to be worth it, let's imagine you want your "todo items" to be polymorphic. For example, you want to be able to add todo items not only to "todo lists" but to many other parts of your application, such as projects, milestones, you name it.

First of all, it is important to remember Ecto does not provide the same type of polymorphic associations available in frameworks such as Rails and Laravel. In such frameworks, a polymorphic association uses two columns, the `parent_id` and `parent_type`. For example, one todo item would have `parent_id` of 1 with `parent_type` of "TodoList" while another would have `parent_id` of 1 with `parent_type` of "Project".

The issue with the design above is that it breaks database references. The database is no longer capable of guaranteeing the item you associate to exists or will continue to exist in the future. This leads to an inconsistent database which end-up pushing workarounds to your application.

The design above is also extremely inefficient, especially if you're working with large tables. Bear in mind that if that's your case, you might be forced to remove such polymorphic references in the future when frequent polymorphic queries start grinding the database to a halt even after adding indexes and optimizing the database.

Luckily, the documentation for the `Ecto.Schema.belongs_to/3` macro includes a section named "Polymorphic associations" with some examples on how to design sane and performant associations. One of those approaches consists in using many join tables. Besides the "todo_lists" and "projects" tables and the "todo_items" table, we would create "todo_list_items" and "project_items" to associate todo items to todo lists and todo items to projects respectively. In terms of migrations, we are looking at the following:

```elixir
create table(:todo_lists)  do
  add :title
  timestamps()
end

create table(:projects)  do
  add :name
  timestamps()
end

create table(:todo_items)  do
  add :description
  timestamps()
end

create table(:todo_list_items) do
  add :todo_item_id, references(:todo_items)
  add :todo_list_id, references(:todo_lists)
  timestamps()
end

create table(:project_items) do
  add :todo_item_id, references(:todo_items)
  add :project_id, references(:projects)
  timestamps()
end
```

By adding one table per association pair, we keep database references and can efficiently perform queries that relies on indexes.

First let's see how to implement this functionality in Ecto using a `has_many :through` and then use `many_to_many` to remove a lot of the boilerplate we were forced to introduce.

## Polymorphism with has_many :through

Given we want our todo items to be polymorphic, we can no longer associate a todo list to todo items directly. Instead we will create an intermediate schema to tie `MyApp.TodoList` and `MyApp.TodoItem` together.

```elixir
defmodule MyApp.TodoList do
  use Ecto.Schema

  schema "todo_lists" do
    field :title
    has_many :todo_list_items, MyApp.TodoListItem
    has_many :todo_items,
      through: [:todo_list_items, :todo_item]
    timestamps()
  end
end

defmodule MyApp.TodoListItem do
  use Ecto.Schema

  schema "todo_list_items" do
    belongs_to :todo_list, MyApp.TodoList
    belongs_to :todo_item, MyApp.TodoItem
    timestamps()
  end
end

defmodule MyApp.TodoItem do
  use Ecto.Schema

  schema "todo_items" do
    field :description
    timestamps()
  end
end
```

Although we introduced `MyApp.TodoListItem` as an intermediate schema, `has_many :through` allows us to access all todo items for any todo list transparently:

```elixir
todo_lists |> Repo.preload(:todo_items)
```

The trouble is that `:through` associations are **read-only** since Ecto does not have enough information to fill in the intermediate schema. This means that, if we still want to use `cast_assoc` to insert a todo list with many todo items directly from the UI, we cannot use the `:through` association and instead must go step by step. We would need to first `cast_assoc(:todo_list_items)` from `TodoList` and then call `cast_assoc(:todo_item)` from the `TodoListItem` schema:

```elixir
# In MyApp.TodoList
def changeset(struct, params \\ %{}) do
  struct
  |> Ecto.Changeset.cast(params, [:title])
  |> Ecto.Changeset.cast_assoc(
    :todo_list_items,
    required: true
  )
end

# And then in the MyApp.TodoListItem
def changeset(struct, params \\ %{}) do
  struct
  |> Ecto.Changeset.cast_assoc(:todo_item, required: true)
end

# And then in MyApp.TodoItem
def changeset(struct, params \\ %{}) do
  struct
  |> Ecto.Changeset.cast(params, [:description])
end
```

To further complicate things, remember `cast_assoc` expects a particular shape of data that reflects your associations. In this case, because of the intermediate schema, the data sent through your forms in Phoenix would have to look as follows:

```elixir
%{"todo_list" => %{
  "title" => "shipping list",
  "todo_list_items" => %{
    0 => %{"todo_item" => %{"description" => "bread"}},
    1 => %{"todo_item" => %{"description" => "eggs"}},
  }
}}
```

To make matters worse, you would have to duplicate this logic for every intermediate schema, and introduce `MyApp.TodoListItem` for todo lists, `MyApp.ProjectItem` for projects, etc.

Luckily, `many_to_many` allows us to remove all of this boilerplate.

## Polymorphism with many_to_many

In a way, the idea behind `many_to_many` associations is that it allows us to associate two schemas via an intermediate schema while automatically taking care of all details about the intermediate schema. Let's rewrite the schemas above to use `many_to_many`:

```elixir
defmodule MyApp.TodoList do
  use Ecto.Schema

  schema "todo_lists" do
    field :title
    many_to_many :todo_items, MyApp.TodoItem,
      join_through: MyApp.TodoListItem
    timestamps()
  end
end

defmodule MyApp.TodoListItem do
  use Ecto.Schema

  schema "todo_list_items" do
    belongs_to :todo_list, MyApp.TodoList
    belongs_to :todo_item, MyApp.TodoItem
    timestamps()
  end
end

defmodule MyApp.TodoItem do
  use Ecto.Schema

  schema "todo_items" do
    field :description
    timestamps()
  end
end
```

Notice `MyApp.TodoList` no longer needs to define a `has_many` association pointing to the `MyApp.TodoListItem` schema and instead we can just associate to `:todo_items` using `many_to_many`.

Differently from `has_many :through`, `many_to_many` associations are also writable. This means we can send data through our forms exactly as we did at the beginning of this guide:

```elixir
%{"todo_list" => %{
  "title" => "shipping list",
  "todo_items" => %{
    0 => %{"description" => "bread"},
    1 => %{"description" => "eggs"},
  }
}}
```

And we no longer need to define a changeset function in the intermediate schema:

```elixir
# In MyApp.TodoList
def changeset(struct, params \\ %{}) do
  struct
  |> Ecto.Changeset.cast(params, [:title])
  |> Ecto.Changeset.cast_assoc(:todo_items, required: true)
end

# And then in MyApp.TodoItem
def changeset(struct, params \\ %{}) do
  struct
  |> Ecto.Changeset.cast(params, [:description])
end
```

In other words, we can use exactly the same code we had in the "todo lists has_many todo items" case. So even when external constraints require us to use a join table, `many_to_many` associations can automatically manage them for us. Everything you know about associations will just work with `many_to_many` associations as well.

Finally, even though we have specified a schema as the `:join_through` option in `many_to_many`, `many_to_many` can also work without intermediate schemas altogether by simply giving it a table name:

```elixir
defmodule MyApp.TodoList do
  use Ecto.Schema

  schema "todo_lists" do
    field :title
    many_to_many :todo_items, MyApp.TodoItem,
      join_through: "todo_list_items"
    timestamps()
  end
end
```

In this case, you can completely remove the `MyApp.TodoListItem` schema from your application and the code above will still work. The only difference is that when using tables, any autogenerated value that is filled by Ecto schema, such as timestamps, won't be filled as we no longer have a schema. To solve this, you can either drop those fields from your migrations or set a default at the database level.

## Summary

In this guide we used `many_to_many` associations to drastically improve a polymorphic association design that relied on `has_many :through`. Our goal was to allow "todo_items" to associate to different entities in our code base, such as "todo_lists" and "projects". We have done this by creating intermediate tables and by using `many_to_many` associations to automatically manage those join tables.

At the end, our schemas may look like:

```elixir
defmodule MyApp.TodoList do
  use Ecto.Schema

  schema "todo_lists" do
    field :title
    many_to_many :todo_items, MyApp.TodoItem,
      join_through: "todo_list_items"
    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [:title])
    |> Ecto.Changeset.cast_assoc(
      :todo_items,
      required: true
    )
  end
end

defmodule MyApp.Project do
  use Ecto.Schema

  schema "projects" do
    field :name
    many_to_many :todo_items, MyApp.TodoItem,
      join_through: "project_items"
    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [:name])
    |> Ecto.Changeset.cast_assoc(
      :todo_items,
      required: true
    )
  end
end

defmodule MyApp.TodoItem do
  use Ecto.Schema

  schema "todo_items" do
    field :description
    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [:description])
  end
end
```

And the database migration:

```elixir
create table("todo_lists")  do
  add :title
  timestamps()
end

create table("projects")  do
  add :name
  timestamps()
end

create table("todo_items")  do
  add :description
  timestamps()
end

# Primary key and timestamps are not required if
# using many_to_many without schemas
create table("todo_list_items", primary_key: false) do
  add :todo_item_id, references(:todo_items)
  add :todo_list_id, references(:todo_lists)
  # timestamps()
end

# Primary key and timestamps are not required if
# using many_to_many without schemas
create table("project_items", primary_key: false) do
  add :todo_item_id, references(:todo_items)
  add :project_id, references(:projects)
  # timestamps()
end
```

Overall our code looks structurally the same as `has_many` would, although at the database level our relationships are expressed with join tables.

While in this guide we changed our code to cope with the parameter format required by `cast_assoc`, in [Constraints and Upserts](Constraints and Upserts.md) we drop `cast_assoc` altogether and use `put_assoc` which brings more flexibilities when working with associations.

## Polymorphism with a self-referencing many_to_many

The aformentioned examples illustrate how we could implement polymorphism between different tables in the database. But, what if we want to reference the same table in the database? This is commonly used for symmetric relationships and is often referred to as self-referencing `many_to_many` association.

Let's imagine we are building a system that supports a model for relationships between people.

```elixir
defmodule MyApp.Accounts.Person do
  use Ecto.Schema
  
  schema "people" do
    field :name, :string
    many_to_many :relationships, MyApp.Accounts.Person, join_through: MyApp.Relationships.Relationship, join_keys: [person_id: :id, relation_id: :id]
    many_to_many :reverse_relationships, MyApp.Accounts.Person, join_through: MyApp.Relationships.Relationship, join_keys: [relation_id: :id, person_id: :id]
    timestamps()
  end
end

defmodule MyApp.Relationships.Relationship do
  use Ecto.Schema

  schema "relationships" do
    field :person_id, :id
    field :relation_id, :id
    timestamps()
  end
end
```

In our example, we implement an intermediate schema, `MyApp.Relationships.Relationship`, on our `:join_through` option and pass in a pair of ids that we will be creating a unique index on in our database migration. By implementing an intermediate schema, we make it easy to add additional attributes and functionality to relationships in the future.

We had to create an additional `many_to_many` `:reverse_relationships` call with an inverse of the `:join_keys` in order to finish the other half of the association. This ensures that both sides of the relationship will get added in the database when either side completes a successul relationship request. 

The person's account who is the inverse of the relationship will have the relationship stored in a "reverse_relationships" key, and we will be able to construct queries for `:reverse_relationships` with the proper `:preload`.

```elixir
iex> people = Repo.all from p in Person, preload: [:relationships, :reverse_relationships]
iex>  [
        MyApp.Accounts.Person<
          ...
          relationships: [
            MyApp.Accounts.Person<
              __meta__: #Ecto.Schema.Metadata<:loaded, "people">,
              ...
            >
          ]
        >,
        MyApp.Accounts.Person<
          ...
          reverse_relationships: [
            MyApp.Accounts.Person<
              __meta__: #Ecto.Schema.Metadata<:loaded, "people">,
              ...
            >
          ]
        >
      ]
```

In the example query above, we are assuming that we have two "people" that have entered into a relationship. Our query illustrates how one person is added on the `:relationships` side and the other on the `:reverse_relationships` side.

It is also worth noticing that we are implementing separate parent modules for both our `Person` and `Relationship` modules. This separation of concerns helps improve code organization and maintainability by allowing us to isolate core functions for relationships in the `MyApp.Relationships` context and vice-versa.

Let's take a look at our "relationships" Ecto migration.

```elixir
def change do
  create table(:relationships) do
    add :person_id, references(:people)
    add :relation_id, references(:people)
    timestamps()
  end

  create index(:relationships, [:person_id])
  create index(:relationships, [:relation_id])
  create unique_index(:relationships, [:person_id, :relation_id], name: :relationships_person_id_relation_id_index)
  create unique_index(:relationships, [:relation_id, :person_id], name: :relationships_relation_id_person_id_index)
end
```

We create indexes on both the `:person_id` and `:relation_id` for quicker access in the future. Then, we create one unique index on the `:relationships` and another unique index on the inverse of `:relationships` to ensure that people cannot have duplicate relationships. Lastly, we pass a name to the `:name` option to help clarify the unique constraint when working with our changeset.

```elixir
# In MyApp.Relationships.Relationship
def changeset(struct, params \\ %{}) do
  struct
  |> Ecto.Changeset.cast(params, [:person_id, :relation_id])
  |> Ecto.Changeset.unique_constraint([:person_id, :relation_id], name: :relationships_person_id_relation_id_index)
  |> Ecto.Changeset.unique_constraint([:relation_id, :person_id], name: :relationships_relation_id_person_id_index)
end
```

Due to the self-referential nature, we will only need to cast the `:join_keys` in order for Ecto to correctly associate the two records in the database. When considering production applications, we will most likely want to add additional attributes and validations, as well as a confirmation system. This is where our isolation of modules will help us maintain and organize the increasing complexity.

## Summary

In this guide we used `many_to_many` associations to implement a self-referencing symmetric relationship. 

Our goal was to allow "people" to associate to different "people". Further, we wanted to lay a strong foundation for code organization and maintainability into the future. We have done this by creating intermediate tables, two separate functional core modules, a clear naming strategy, an inverse association, and by using `many_to_many` `:join_keys` to automatically manage those join tables.

At the end, our schemas may look like:

```elixir
defmodule MyApp.Accounts.Person do
  use Ecto.Schema
  
  schema "people" do
    field :name, :string
    many_to_many :relationships, MyApp.Accounts.Person, join_through: MyApp.Relationships.Relationship, join_keys: [person_id: :id, relation_id: :id]
    many_to_many :reverse_relationships, MyApp.Accounts.Person, join_through: MyApp.Relationships.Relationship, join_keys: [relation_id: :id, person_id: :id]
    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [:name])
  end
end

defmodule MyApp.Relationships.Relationship do
  use Ecto.Schema

  schema "relationships" do
    field :person_id, :id
    field :relation_id, :id
    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [:person_id, :relation_id])
    |> Ecto.Changeset.unique_constraint([:person_id, :relation_id], name: :relationships_person_id_relation_id_index)
    |> Ecto.Changeset.unique_constraint([:relation_id, :person_id], name: :relationships_relation_id_person_id_index)
  end
end
```

And the database migrations:

```elixir
def change do
  create table(:people) do
    add :name, :string
    timestamps()
end

def change do
  create table(:relationships) do
    add :person_id, references(:people)
    add :relation_id, references(:people)
    timestamps()
  end

  create index(:relationships, [:person_id])
  create index(:relationships, [:relation_id])
  create unique_index(:relationships, [:person_id, :relation_id], name: :relationships_person_id_relation_id_index)
  create unique_index(:relationships, [:relation_id, :person_id], name: :relationships_relation_id_person_id_index)
end
```

Overall, our code contains a small structural modification, when compared with a typical `many_to_many`, in order to implement an inverse join between our self-referenced table and schema.

Where we go from here will depend greatly on the specific needs of our application. If we remember to adhere to our clear naming strategy with a strong separation of concerns, we will go a long way in keeping our self-referencing `many_to_many` association organized and easier to maintain.