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

> Actually, the `bought_from` should be also a `belongs_to` relation, pointing to a table with nurseries, or contacts. But
> there's more to come, so let's keep it like this for the time being.

What does the `belongs_to` macro really do?  Let's have a look by letting Ecto create our database according to this schema.

You came here after doing the more introductiory how-tos and tutorials, so you know how to set up an Elixir project, how to
configure your Ecto-DBMS connection, how to have Ecto create a database, and you know how to handle migrations.



## Life is complex, but we can model it

You must have heard of those funny names biologists use, like saying Canis lupus familiaris when all they mean is "dog", or when
they confuse you with Origanum majorana and what is the reason that common oregano should be vulgar? If you have been in the
Tropics, you surely noticed how easy it is to confuse a banana plant with a flowerless heliconia, and with other plants that
provide no fruit nor carry any particularly showy flowers. They are all related: common oregano and marjoram both belong to the
Origanum genus, while all bananas, heliconias, ginger, and bihao belong to the Zingiberales order.

If you think this is a complex example, well, we are using this example precisely because it's a complex one, coming from real
life, and not the rather tedious and far too simplistic *Library* example. We will not need to invent stories here, and you will
be able to find background information, to make sense of the complexity we are modelling, by checking reference sources, like the
Wikipedia, or sites like https://atlasoflife.org.au/, or http://tropicos.org/. Enjoy reading, and enjoy nature!

Oh, and back to Zingiberales, Ginger is also one of them.

## Modelling taxonomic information

The above lengthy explanation is to introduce the need for self-relations. Taxonomists speak of a `Taxon`, which is a concept
that encompasses Reigns, Genera, Species, Varieties, and several more.  Each of these names is a `Rank`, and a taxon has a rank
(or, in Ecto terms, it `belongs_to` a rank), and also belongs to one taxon at a higher rank. A `Rank` has a name, and we could
add an integer value to represent depth in the taxonomy tree of life, but let's forget about that for the time being.


```iex
defmodule Taxonomy.Rank do
  use Ecto.Schema

  schema "ranks" do
    field :name, string
  end
end

defmodule Taxonomy.taxon do
  use Ecto.Schema

  schema "taxa" do
    field :epithet, string
    field :authorship, string
    field :publication_year, integer
    belongs_to :parent, Taxonomy.taxon
    belongs_to :rank, Taxonomy.Rank
  end
end
```



## Modelling a garden
