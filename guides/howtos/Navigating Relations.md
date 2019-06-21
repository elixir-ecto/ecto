# Navigating Relations

In this guide we will learn how to work with relations between tables. We will do so, building a small
real-life database structure with several related tables, modelling taxonomic information, and a plant collection.

Speaking in SQL terms, we have a relation wherever a field in a table is marked as a `Foreign Key`, 
so that it `References` a `Primary Key` in an other table.  We have a self-relation where the target table
coincides with the origin table.

Ecto has several macros letting us define SQL relations, and navigate them, mostly allowing us to focus
on meaning rather than the technical details.  We will introduce them as we go, here we merely mention them,
so you know what to expect from reading this page: `belongs_to`, `has_many`, `has_one`, `many_to_many`.

## Modelling a garden

Let's start from the easy part. We have a rather large garden, we put plants in it, we want to find them back. 
So we draw a map of the garden, this is paperwork, and we define beds, or locations, in the garden. These have a name
(humans need names) and a code (for in the map).  Let's also add a description, for more verbose needs.  
**TODO: we will add length limit to `name` and a much larger to `description`**

```iex
defmodule Garden.Location do
  use Ecto.Schema

  schema "locations" do
    field :code, string
    field :name, string
    field :description, string
  end
end
```

Now, when we put a plant in the garden, we want it to refer to a location, so the database will help us
when we need to look for it.  **TODO correct the type of the `bought_on` field**

```iex
defmodule Garden.Plant do
  use Ecto.Schema

  schema "plants" do
    belongs_to :location, Garden.Location
    field :name, string
    field :bought_on, string
    field :bought_from, string
  end
end
```

> Actually, the `bought_from` should be also a `belongs_to` relation, pointing to a table with nurseries, or contacts.
But there's more to come, so let's keep it like this for the time being.

What does the `belongs_to` macro really do?  Let's have a look by letting Ecto create our database according to this schema.
