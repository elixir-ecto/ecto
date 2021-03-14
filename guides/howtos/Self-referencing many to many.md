# Self-referencing many to many

`Ecto.Schema.many_to_many/3` is used to establish the association between two schemas with a join table (or a join schema) tracking the relationship between them. But, what if we want the same table to reference itself? This is commonly used for symmetric relationships and is often referred to as a self-referencing `many_to_many` association.

## People relationships

Let's imagine we are building a system that supports a model for relationships between people.

```elixir
defmodule MyApp.Accounts.Person do
  use Ecto.Schema
  
  alias MyApp.Accounts.Person
  alias MyApp.Relationships.Relationship

  schema "people" do
    field :name, :string

    many_to_many :relationships,
                 Person,
                 join_through: Relationship,
                 join_keys: [person_id: :id, relation_id: :id]

    many_to_many :reverse_relationships,
                 Person,
                 join_through: Relationship,
                 join_keys: [relation_id: :id, person_id: :id]

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

We had to create an additional `many_to_many` `:reverse_relationships` call with an inverse of the `:join_keys` in order to finish the other half of the association. This ensures that both sides of the relationship will get added in the database when either side completes a successful relationship request. 

The person who is the inverse of the relationship will have the relationship struct stored in a list under the "reverse_relationships" key. We can then construct queries for both `:relationships` and `:reverse_relationships` with the proper `:preload`:

```elixir
iex> preloads = [:relationships, :reverse_relationships]
iex> people = Repo.all from p in Person, preload: preloads
[
  MyApp.Accounts.Person<
    ...
    relationships: [
      MyApp.Accounts.Person<
        id: ...,
        ...
      >
    ]
  >,
  MyApp.Accounts.Person<
    ...
    reverse_relationships: [
      MyApp.Accounts.Person<
        id: ...,
        ...
      >
    ]
  >
]
```

In the example query above, we are assuming that we have two "people" that have entered into a relationship. Our query illustrates how one person is added on the `:relationships` side and the other on the `:reverse_relationships` side.

It is also worth noticing that we are implementing separate parent modules for both our `Person` and `Relationship` modules. This separation of concerns helps improve code organization and maintainability by allowing us to isolate core functions for relationships in the `MyApp.Relationships` context and vice-versa.

Let's take a look at our Ecto migration:

```elixir
def change do
  create table(:relationships) do
    add :person_id, references(:people)
    add :relation_id, references(:people)
    timestamps()
  end

  create index(:relationships, [:person_id])
  create index(:relationships, [:relation_id])

  create unique_index(
    :relationships,
    [:person_id, :relation_id],
    name: :relationships_person_id_relation_id_index
  )

  create unique_index(
    :relationships,
    [:relation_id, :person_id],
    name: :relationships_relation_id_person_id_index
  )
end
```

We create indexes on both the `:person_id` and `:relation_id` for quicker access in the future. Then, we create one unique index on the `:relationships` and another unique index on the inverse of `:relationships` to ensure that people cannot have duplicate relationships. Lastly, we pass a name to the `:name` option to help clarify the unique constraint when working with our changeset.

```elixir
# In MyApp.Relationships.Relationship
@attrs [:person_id, :relation_id]

def changeset(struct, params \\ %{}) do
  struct
  |> Ecto.Changeset.cast(params, @attrs)
  |> Ecto.Changeset.unique_constraint(
    [:person_id, :relation_id],
    name: :relationships_person_id_relation_id_index
  )
  |> Ecto.Changeset.unique_constraint(
    [:relation_id, :person_id],
    name: :relationships_relation_id_person_id_index
  )
end
```

Due to the self-referential nature, we will only need to cast the `:join_keys` in order for Ecto to correctly associate the two records in the database. When considering production applications, we will most likely want to add additional attributes and validations. This is where our isolation of modules will help us maintain and organize the increasing complexity.

## Summary

In this guide we used `many_to_many` associations to implement a self-referencing symmetric relationship. 

Our goal was to allow "people" to associate to different "people". Further, we wanted to lay a strong foundation for code organization and maintainability into the future. We have done this by creating intermediate tables, two separate functional core modules, a clear naming strategy, an inverse association, and by using `many_to_many` `:join_keys` to automatically manage those join tables.

Overall, our code contains a small structural modification, when compared with a typical `many_to_many`, in order to implement an inverse join between our self-referenced table and schema.

Where we go from here will depend greatly on the specific needs of our application. If we remember to adhere to our clear naming strategy with a strong separation of concerns, we will go a long way in keeping our self-referencing `many_to_many` association organized and easier to maintain.
