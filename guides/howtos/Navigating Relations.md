# Navigating Relations

In this guide we will learn how to work with relations between tables. We will do so, building a small
real-life database structure with several related tables, modelling taxonomic information, and a plant collection.

Speaking in SQL terms, we have a relation wherever a field in a table is marked as a `Foreign Key`, so that it `References` a
`Primary Key` in an other table.  We have a self-relation where the target table coincides with the origin table. We will explore
both. When more objects in one table may be linked with more objects in the target table, we speak of a many-to-many relation,
and we need an intermediate table, we will learn this too. Such an intermediate table may contain information by its own right,
and this too we're going to explore, stepwise.

Ecto has several macros letting us define SQL relations, and navigate them, mostly allowing us to focus
on meaning rather than the technical details.  We will introduce them as we go, here we merely mention them,
so you know what to expect from reading this page: `belongs_to`, `has_many`, `has_one`, `many_to_many`.

## Modelling a garden

Let's start from describing the data we want to represent.

Say we have a rather large garden, that we keep plants in it, and we want software that helps us to find them back.  So we do
some paperwork, draw a map of the garden, and we define beds, or locations, in the garden. These have a name (humans need names)
and a code (for in the map).  Let's also add a description, for more verbose needs.  **TODO: we will add length limit to `name`
and a much larger to `description`**

```iex
defmodule Garden.Location do
  use Ecto.Schema

  schema "locations" do
    field :code, :string
    field :name, :string
    field :description, :string
  end
end
```

Now, when we put a plant in the garden, we want it to refer to a location, so the database will help us
when we need to look for it.

But wait, where should I put these files? Don't we first need an Ecto project? Oh, you mean you need help with that, too? Ok, no
problem, let's do that first.

## Create the project, and the database

The following steps, you should know what they mean and why they're necessary. The two `sed` instructions are for the laziest
among us, who do not want to edit text files. Make sure you have a postgres user with the create database privilege, and `export`
its name and password into the environment variables `USERNAME` and `PASSWORD`, respectively. Please be serious and do not put
forward slashes in name or password, no spaces, nor other things that will be interpreted by the `bash`, thank you.

```bash
export USERNAME=/fill in the blanks/
export PASSWORD=/fill in the blanks/
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

## The first two schemas

Now that we have a complete project structure, and a database, we can put the above `Garden.Location` module in the
`lib/garden/location.ex` file, and create a `plant.ex` file next to it, defining the `Garden.Plant` module:

```iex
defmodule Garden.Plant do
  use Ecto.Schema

  schema "plants" do
    belongs_to :location, Garden.Location
    field :name, :string
    field :species, :string
    field :bought_on, utc_datetime
    field :bought_from, :string
  end
end
```

> To be true, the `bought_from` should be also a `belongs_to` relation, pointing to a table with contacts, like friends, other
> gardens, commercial nurseries. But since there's so much more to come, let's keep it like this for the time being.

What does the `belongs_to` macro really do?  How does impact our physical database structure?  It would be nice if it was the
system telling us, but in reality, it's us who need to tell the system, by writing the corresponding migration.

## The initial migration

You came here after doing the more introductiory how-tos and tutorials, so you know how to set up an Elixir project, how to
configure your Ecto-DBMS connection, how to have Ecto create a database, and you know how to handle migrations.

> Remember that Ecto does keep track of database changes through migrations, yet it is not particularly helpful when it comes to
> writing the migration corresponding to what we change in the schemas. Until there is a `mix` recipe for computing migrations
> (**TODO** anybody interested in reverse engineer django's migrations?), we need to write things twice: once in the schemas, and
> again in migration files.

So let's get to work and write our first migration, relative to moving from an empty database to one with the above schema
definitions. We create a boilerplate named migration, and call it `initial_migration`,

```
mix ecto.gen.migration initial_migration
```

and we fill in the blanks in the newly created file:

```iex
defmodule Botany.Repo.Migrations.InitialMigration do
  use Ecto.Migration

  def change do
    create table(:locations) do
      add :code, :string
      add :name, :string
      add :description, :string
    end

    create table(:plants) do
      add :location_id, references(:locations)
      add :name, :string
      add :species, :string
      add :bought_on, :utc_datetime
      add :bought_from, :string
    end
  end
end
```

For every `field`, we just copied the definition, and replaced the word `field` with `add`.

For the `belongs_to` line from the plants schema, we've written a `location_id` line in the `plants` create table, referring to
the `locations` table. This implies we use its default primary key, `id`. Obviously, for the migration to work, the `create
table(:locations)` must precede the creation of the `plants` table, since we're referring the first from the second.

With this `initial_migration` in place, let's apply it, so that we can finally have a look at the database tables.

```
mix ecto.migrate
```

If all is well, the output is just four `[info]` lines.

We have added quite a few files to our project, and altered others, let's do some housekeeping,

```
git add lib/botany/*.ex mix.lock priv config/config.exs
git commit -m "first migration"
```

## Looking at it from SQL

Fine, it took time, but we now have our updated schema, where we can check the meaning of `belongs_to`. To have a look, we need
to connect directly to the database, not through Elixir.

Let's use the `psql` prompt (if you commonly use something else, you should know the commands corresponding to what we show
here). Our database is called `botany_repo` and you know your user and password. From inside the `psql` prompt, give:

```
\dt
\d plants
\d locations
```

> En passant, have a look at the `schema_migrations` table and content, just to be aware of it.

What is relevant to us here is the `CONSTRAINT` block at the end of each table. Ecto not only created the columns, it also made
our database aware of the meaning of the `location_id` in `plants`, and that it impacts the `locations` table as well.

Since we're here in the database, let's create a few database records, so we save time in the `iex` session.  More than a few in
reality, because we're out to navigating information with real data. (If there's botanists among you, please be assured we are on
our way to do some proper work, I know this is *not* how to model botanic data.)

```sql
insert into locations (id, code, name) values (1, 'GH1', 'tropical greenhouse'),
    (2, 'GH2', 'mediterranean'), (3, 'B01', 'entrance front'), (4, 'B02', 'left of main path-1'),
    (5, 'B04', 'left of main path-2'), (6, 'B06', 'left of main path-3'), (7, 'B03', 'right of main path-1'),
    (8, 'B05', 'right of main path-2'), (9, 'B07', 'right of main path-3');
insert into plants (id, location_id, name, species) values
    ( 1,8,'2018.0002.1','Allium ursinum'),
    ( 2,5,'2018.0003.1','Arctostaphylos uva-ursi'),
    ( 3,1,'2018.0004.1','Aquilegia vulgaris'),
    ( 4,1,'2018.0005.1','Pulsatilla vulgaris'),
    ( 5,6,'2018.0006.1','Armoracia rusticana'),
    ( 6,9,'2018.0007.1','Artemisia abrotanum'),
    ( 7,2,'2018.0008.1','Chelidonium majus'),
    ( 8,1,'2018.0010.1','Digitalis purpurea'),
    ( 9,5,'2018.0011.1','Convallaria majalis'),
    (10,5,'2018.0014.1','Stachys officinalis'),
    (11,5,'2018.0016.1','Artemisia absinthium'),
    (12,8,'2018.0004.2','Aquilegia vulgaris'),
    (13,7,'2018.0017.1','Angelica archangelica'),
    (14,6,'2018.0019.1','Allium schoenoprasum'),
    (15,5,'2018.0020.1','Alchemilla xanthochlora'),
    (16,8,'2018.0021.1','Agrimonia eupatoria'),
    (17,3,'2018.0001.2','Achillea millefolium'),
    (18,3,'2018.0018.2','Althaea officinalis'),
    (19,8,'2018.0027.1','Salvia officinalis'),
    (20,4,'2018.0028.1','Ruta graveolens'),
    (21,2,'2018.0031.1','Paeonia officinalis'),
    (22,2,'2018.0032.1','Leonurus cardiaca'),
    (23,2,'2018.0033.1','Inula helenium'),
    (24,2,'2018.0034.1','Valeriana officinalis'),
    (25,2,'2018.0035.1','Tanacetum vulgare'),
    (26,2,'2018.0036.1','Symphytum officinale'),
    (27,6,'2018.0037.1','Iris germanica'),
    (28,5,'2018.0038.1','Ononis spinosa'),
    (29,4,'2018.0040.1','Pulmonaria officinalis'),
    (30,7,'2018.0041.1','Myrica gale'),
    (31,9,'2018.0044.1','Sanguisorba officinalis'),
    (32,9,'2018.0045.1','Sanguisorba minor'),
    (33,1,'2018.0053.1','Borago officinalis'),
    (34,1,'2018.0054.1','Dryopteris filix-mas'),
    (35,6,'2018.0057.1','Foeniculum vulgare'),
    (36,1,'2018.0060.1','Helleborus niger'),
    (37,8,'2018.0034.2','Valeriana officinalis'),
    (38,5,'2018.0062.1','Sinapis alba'),
    (39,3,'2018.0063.1','Melissa officinalis'),
    (40,3,'2018.0064.1','Viola odorata');
```

## Navigating, forward

This is nice, now we can switch to iex, which we start as `iex -S mix`, and have a look.

```iex
iex> Garden.Plant
Garden.Plant
iex> Garden.Plant |> Ecto.Query.first
#Ecto.Query<from p0 in Garden.Plant, order_by: [asc: p0.id], limit: 1>
```

We gave two instructions, we are not yet there.  With `Garden.Plant`, we mentioned our module, which is just our module,
*duh!*. With `Garden.Plant |> Ecto.Query.first`, we built a query on the schema in our module, and this is a query, we still did
not hit the database.

To hit the database, we have to execute the query, something we can do by `Garden.Plant |> Ecto.Query.first |> Botany.Repo.one`.
This handles the query to `Botany.Repo.one`, which executes it, asserting it should return one or zero records.

```iex
iex> Garden.Plant |> Ecto.Query.first |> Botany.Repo.one

09:54:00.985 [debug] QUERY OK source="plants" db=0.7ms
SELECT p0."id", p0."location_id", p0."name", p0."species", p0."bought_on", p0."bought_from" FROM "plants" AS p0 ORDER BY p0."id" LIMIT 1 []
%Garden.Plant{
  __meta__: #Ecto.Schema.Metadata<:loaded, "plants">,
  bought_from: nil,
  bought_on: nil,
  id: 1,
  location: #Ecto.Association.NotLoaded<association :location is not loaded>,
  location_id: 8,
  name: "2018.0002.1",
  species: "Allium ursinum"
}
```

What happens here is finally *almost* what we are aiming at. We got everything from the `plants` table, including obviously the
`location_id` (hey, but isn't it funny? We added it in the `create table` block, but did not define it in the schema), and
there's a curious `NotLoaded` association in the `location` field (which, heck, think of it, we never saw in the database table).

Apart from the `NotLoaded` which we will explore shortly, all the above is precisely the effect of that `belongs_to` macro in our
schema and that `references` in the migration.

Let's `preload` the relation! (and by the way let's type a few aliases for our tables.)

```iex
iex> alias Garden.Plant
Garden.Plant
iex> alias Garden.Location
Garden.Location
iex> Plant |> Ecto.Query.first |> Botany.Repo.one |> Botany.Repo.preload(:location)

10:05:47.533 [debug] QUERY OK source="plants" db=2.3ms queue=0.1ms
SELECT p0."id", p0."location_id", p0."name", p0."species", p0."bought_on", p0."bought_from" FROM "plants" AS p0 ORDER BY p0."id" LIMIT 1 []

10:05:47.536 [debug] QUERY OK source="locations" db=2.2ms queue=0.1ms
SELECT l0."id", l0."code", l0."name", l0."description", l0."id" FROM "locations" AS l0 WHERE (l0."id" = $1) [8]
%Garden.Plant{
  __meta__: #Ecto.Schema.Metadata<:loaded, "plants">,
  bought_from: nil,
  bought_on: nil,
  id: 1,
  location: %Garden.Location{
    __meta__: #Ecto.Schema.Metadata<:loaded, "locations">,
    code: "B05",
    description: nil,
    id: 8,
    name: "right of main path-2"
  },
  location_id: 8,
  name: "2018.0002.1",
  species: "Allium ursinum"
}
```

Now we hit the database twice, and got a `%Location` structure within our `%Plant` structure, associated, as we expected, to the
`location` field. Let's do it better, matching it to a `p1` variable.

```iex
iex> p1 = Plant |> Ecto.Query.first |> Botany.Repo.one |> Botany.Repo.preload(:location)
```

And let's now match `loc8` to our plant location:

```iex
iex> %Plant{location: loc8} = p1
```

Right, we could have done it differently:

```iex
iex> loc8 = p1.location
```

Whatever looks easier, or clearer to you in the context. I like the first one better, because we also assert that `p1` is a
`Plant` structure. In both cases, we're using the effects of the `belongs_to` macro.

If we had matched the `p1` variable to the expression without the `preload` trailing pipe, we could still add that part, at any
intermediate moment before matching the field to the `loc8` variable. Do remember that we are still in an environment where
objects are immutable, so matching `p1` to the expression missing the `preload` part will be just that, a match to an immutable
expression. If you later add the `preload` pipe to it, you should match a variable to it, like this, where we're reusing the same
variable:

```iex
iex> p1 = p1 |> Botany.Repo.preload(:location)
```

It does no harm evaluating a `preload` on a preloaded field, it's an idempotent function.

## Navigating, backwards

Let's choose a location, and let's say we want to have all its plants. For ease of typing, let's import the `Ecto.Query` module.

```iex
iex> import Ecto.Query
iex> gh1 = (from l in Location, where: l.code=="GH1") |> Botany.Repo.one
```

How do we do that… I would like to just type `gh1.plants`, doesn't it make sense, possibly after a `preload`… As of now, all I
can think of is to type a complete query!

```iex
iex> q = from p in Plant, where: p.location_id==^gh1.id
iex> q |> Botany.Repo.all
```

With what we have, we can go up the links, by this I mean that we can get the `location` from a plant, but Ecto can help us move
in the other direction too, as we're trying to do here. This is precisely what the macro `has_many` offers us. Open the
`location.ex` file and add a single line in the schema.

```iex
defmodule Garden.Location do
  use Ecto.Schema

  schema "locations" do
    has_many :plants, Garden.Plant  # backward link
    field :code, string
    field :name, string
    field :description, string
  end
end
```

`recompile`, and reload the structure for location `gh1`.  You will notice, it holds the new `plants` field, again in need of
`preload`. You know how to do that, and you will get a nicely populated `gh1.plants` field, with a list of `%Plant` structures.
You should be surprised, or maybe not, for we did not need any migration.

Other than `belongs_to`, `has_many` does not cause any change on the physical database schema, it just informs Ecto that there is
already a link leading here, where to find its definition, and that we want to navigate it in the opposite direction.

Have fun with the project and the data, explore, learn, understand, and take a well deserved pause: There's much more to come,
and it's not going to be easy.

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
    field :code, :string
    field :orig_quantity, :integer
    field :bought_on, utc_datetime
    field :bought_from, :string
  end
end

defmodule Garden.Plant do
  use Ecto.Schema

  schema "plants" do
    belongs_to :location, Garden.Location
    belongs_to :accession, Garden.Accession
    field :code, :string
    field :quantity, :integer
  end
end
```
