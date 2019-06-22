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

Let's start from describing the data we want to represent.

Say we have a rather large garden, that we keep plants in it, and we want software that helsp us to find them back.  So we do
some paperwork, draw a map of the garden, and we define beds, or locations, in the garden. These have a name (humans need names)
and a code (for in the map).  Let's also add a description, for more verbose needs.  **TODO: we will add length limit to `name`
and a much larger to `description`**

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
when we need to look for it.

But wait, where should I put these files? Don't we first need an Ecto project?

## Create the project, and the database

The following steps, you should know what they mean and why they're necessary. The two `sed` instructions are for the laziest
among us, who do not want to edit text files. Make sure you have a postgres user with the create database privilege, and `export`
its name and password into the environment variables `USERNAME` and `PASSWORD`, respectively. Please be serious and do not put
forward slashes in name or password, no spaces, nor other things that will be interpreted by the `bash`, thank you.

```bash
export USERNAME=<fill in the blanks>
export PASSWORD=<fill in the blanks>
mix new botany --sup
cd botany
sed mix.exs -i -e '/defp deps do/,/end/s/\[/\[\n      {:ecto_sql, "~> 3.0"},\n      {:postgrex, ">= 0.0.0"},/'
git init .
git add .
git commit -m "initial commit"
mix deps.get
mix ecto.gen.repo -r Botany.Repo
sed config/config.exs -i -e '/username/s/".*"/"'$USERNAME'"/' -e '/password/s/".*"/"'$PASSWORD'"/'
(echo; echo "    config :botany,"; echo "      ecto_repos: [Botany.Repo]") >> config/config.exs
sed lib/botany/application.ex -i -e '/def start/,/end/s/\(# {Botany.Worker, arg}\)/\1\n      {Botany.Repo, []},/'
mix ecto.create
```

The above commands should lead to this last output line:

```
The database for Botany.Repo has been created
```

If so, fine, and continue, otherwise please go back to more basic documentation, and come back with your homework done.

Oh, and if you wonder why on earth not give manual instructions? This way you can any time safely drop your database, restart
this tutorial page by simply copy-pasting the above lines into your bash prompt. Works equally well on OSX and GNU/Linux. If
you're on Windows, what a pity.

## Back to work

Now that we have a complete structure, and a database, we can put the above Location module in the `lib/garden/location.ex` file,
and create a `plant.ex` file next to it, with this content.

```iex
defmodule Garden.Plant do
  use Ecto.Schema

  schema "plants" do
    belongs_to :location, Garden.Location
    field :name, string
    field :bought_on, utc_datetime
    field :bought_from, string
  end
end
```

> Actually, the `bought_from` should be also a `belongs_to` relation, pointing to a table with contacts, like friends, other
> gardens, commercial nurseries. But since there's so much more to come, let's keep it like this for the time being.

What does the `belongs_to` macro really do?  How does impact our physical database structure?  For this, we need to update the
database structure with the new definitions, that is, we need a migration.

You came here after doing the more introductiory how-tos and tutorials, so you know how to set up an Elixir project, how to
configure your Ecto-DBMS connection, how to have Ecto create a database, and you know how to handle migrations.

Remember that Ecto does keep track of database changes through migrations, yet it is not particularly helpful when it comes to
writing such migrations. Until there is a `mix` recipe for computing migrations (it could do so, from the current schemas and the
cumulative effect of all existing migrations), we need to write things twice: once in the schemas, and again in migration
files. So let's get to work and write our first migration, relative to moving from an empty database to one with the above schema
definitions.

**TODO**

With the initial migration in place, let's apply it, so that we can finally have a look at the database tables.

```
mix ecto.migrate
```

Fine, it took time, but we now have our updated schema, where we can check the meaning of `belongs_to`. To have a look, we need
to connect directly to the database, not through Elixir.

Let's use the `psql` prompt (if you commonly use something else, you should know the commands corresponding to what we show
here). Our database is called `botany_repo` and you know your user and password. From inside the `psql` prompt, give:

```
\dt
\d plants
\d locations
```

**TODO - review the tables, and comment on what we see.**

Now some real work: with this database, we can add a few locations and some plants.

**TODO - start iex and among others, matched a variable to location structure code:GH1**

Notice how we can go up the links, by this I mean that we can get the `location` from a plant, but it would also be nice to move
in the other direction, for example once we matched a `location` variable to a structure represeting location `GH1`, it would be
good to know what plants are placed there, by writing `location.plants`, without having to look up the `id` of the structure, and
write the query:

```
from p in Plant, where p.location_id==loc_id
```

This is precisely what the macro `has_many` offers us. 

```iex
defmodule Garden.Location do
  use Ecto.Schema

  schema "locations" do
    has_many :plants, Garden.Plant
    field :code, string
    field :name, string
    field :description, string
  end
end
```

`recompile`, and reload the structure for location `GH1`.  You can now evaluate `location.plants`.  You should be surprised, or
maybe not, for we did not need any migration.

Other than `belongs_to`, `has_many` does not cause any change on the physical database schema, it just informs Ecto that there is
already a link leading here, where to find its definition, and that we want to navigate it in the opposite direction.

## Life is complex, but we can model it

You must have heard of those funny names biologists use, like they say Canis lupus familiaris when all they mean is "dog", or
when they confuse you with Origanum majorana and what is the reason that common oregano should be vulgar? Also, if you have been
in the Tropics, you surely noticed how easy it is to confuse a banana plant with larger flowerless heliconia, and with other
plants that provide no fruit nor carry any particularly showy flowers. They are all related: common oregano and marjoram both
belong to the Origanum genus, while bananas, heliconias, and bihao belong to the Zingiberales order, and all are vascular plants.

If you think this is a complex example, well, we are using this example precisely because it's a complex one, coming from real
life, and not the rather tedious and far too simplistic *Library* example. We will not need to invent stories here, and you will
be able to find background information, to make sense of the complexity we are modelling, by checking reference sources, like the
Wikipedia, or sites like https://atlasoflife.org.au/, or http://tropicos.org/. Enjoy reading, and enjoy nature!

Oh, and back to Zingiberales, Ginger —Zingiber— is also one of them.

## Modelling taxonomic information

The above lengthy explanation is to introduce the need for self-relations. Taxonomists speak of a `Taxon`, which is a concept
that encompasses Orders, Genera, Species, and several more.  Each of these names identifies a `Rank`, and a taxon has a rank (or,
in Ecto terms, it `belongs_to` a rank), and also belongs to one taxon at a higher rank. A `Rank` has a name, and we could add an
integer value to represent depth in the taxonomy tree of life, but let's forget about that for the time being.

The above mentioned taxa ('taxa' is the Greek plural form for taxon) are so organized:

```
Tracheophyta
 |--Zingiberales
 |  |--Musaceae
 |  |  |--Musa
 |  |
 |  |--Zingiberaceae
 |  |  |--Zingiber
 |  |
 |  |--Heliconiaceae
 |     |--Heliconia
 |
 |--Lamiales
    |--Lamiaceae
       |--Origanum
          |--Origanum vulgare
          |--Origanum majorana
```

Here we have one "Division", two "Orders", four "Families" and we only mentioned one genus per family, plus we have two species
in the Origanum genus. The two corresponding tables are not complicated after all, and allow us represent the above information.

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
    belongs_to :parent, Taxonomy.taxon
    belongs_to :rank, Taxonomy.Rank
  end
end
```
Let's now add the few taxa we introduced above.

**TODO**

```iex
defmodule Taxonomy.taxon do
  use Ecto.Schema

  schema "taxa" do
    field :epithet, string
    has_many :children, Taxonomy.Taxon
    belongs_to :parent, Taxonomy.Taxon
    belongs_to :rank, Taxonomy.Rank
  end
end
```

## Modelling a garden

When a gardener acquires a plant, they seldom acquire just one for each species, it's often in batches, all same source, same
time, and then these plants may end in different locations in the garden. To make sure that the physical plants are kept together
conceptually, we introduce a library science concept into our botanical collection: an "Accession". This allow us keeping
together plants of the same species, which were acquired together. It also simplifies connecting plants to taxa: if a taxonomist
tells you that some individual plant belongs to some species, this opinion will apply to all plants in the same accession.

Let's correct the `Garden.Plant` module, and create a new `Garden.Accession` module.

```iex
defmodule Garden.Accession do
  use Ecto.Schema

  schema "accessions" do
    belongs_to :taxon, Taxonomy.Taxon
    field :code, string
    field :orig_quantity, integer
    field :bought_on, utc_datetime
    field :bought_from, string
  end
end

defmodule Garden.Plant do
  use Ecto.Schema

  schema "plants" do
    belongs_to :location, Garden.Location
    belongs_to :accession, Garden.Accession
    field :code, string
    field :quantity, integer
  end
end
```

