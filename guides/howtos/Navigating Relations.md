# Navigating Relations

In this guide we will learn how to work with relations between tables.  We will proceed by
building a small real-life database structure with several related tables, modelling taxonomic
information, and a plant collection.

Speaking in SQL terms, we have a relation wherever a field in a table is marked as a `Foreign
Key`, so that it `References` a `Primary Key` in an other table.  SQL can prescribe actions,
associated to a `on delete` event on one side of the relation, and Ecto gives us tools to
define this action.  We will also explore self-relations, where the target table coincides with
the origin table, and multiple cases of self-relations.  When more objects in one table may be
linked with more objects in the target table, we speak of a many-to-many relation, and we need
an intermediate table, we will learn this too.  Such an intermediate table may contain
information by its own right, and this too we're going to explore, stepwise.

Ecto has several macros letting us define SQL relations, and navigate them, mostly allowing us
to focus on meaning rather than the technical details.  We will introduce them as we go, here
we merely mention them, so you know what to expect from reading this page: `belongs_to`,
`has_many`, `has_one`, `many_to_many`.

The *stepwise* approach will require us that we write migrations.  While we assume you know all
about them, we are anyway going to be quite specific about that part too, for we are going to
migrate relational links.

If you opt to use this text as a tutorial, try to dedicate between 2 and 4 hours for each
section, and take some time between them.  Each has a subtitle "*day i*", as if you were
working 3 hours a day.  Ancient Romans conquered the world at this pace.

## Modelling a garden
*day 1*

Let's start from describing the data we want to represent.

Say we have a rather large garden, that we keep plants in it, and we want software that helps us
to find them back.  So we do some paperwork, draw a map of the garden, and we define beds, or
locations, in the garden.  These have a name (humans need names) and a code (for in the map).
Let's also add a description, for more verbose needs.  **TODO: we will add length limit to
`name` and a much larger to `description`**

```iex
defmodule Botany.Location do
  use Ecto.Schema

  schema "location" do
    field :code, :string
    field :name, :string
    field :description, :string
  end
end
```

Now, when we put a plant in the garden, we want it to refer to a location, so the database will
help us when we need to look for it.

But wait, where should I put these files? Don't we first need an Ecto project? Oh, you mean you
need help with that, too? Ok, no problem, let's do that first.

### Create the project, and the database

The following steps, you should know what they mean and why they're necessary.  The two `sed`
instructions are for the laziest among us, who do not want to edit text files.  Make sure you
have a PostgreSQL user with the create database privilege, and `export` its name and password
into the environment variables `USERNAME` and `PASSWORD`, respectively.  Please be serious and
do not put forward slashes in name or password, no spaces, nor other things that will be
interpreted by the `bash`, thank you.

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

If so, fine, and continue, otherwise please go back to more basic documentation, and come back
with your homework done.

Oh, and if you wonder why on earth not give manual instructions? This way you can any time
safely drop your database, remove the whole project directory structure, and restart this
tutorial page, by simply copy-pasting the above lines into your bash prompt.  Works equally
well on OSX and GNU/Linux.  If you're on Windows, what a pity.

### The first two schemas

Now that we have a complete project structure, and a database, we can put the above
`Botany.Location` module in the `lib/garden/location.ex` file, and create a `plant.ex` file
next to it, defining the `Botany.Plant` module:

```iex
defmodule Botany.Plant do
  use Ecto.Schema

  schema "plant" do
    belongs_to :location, Botany.Location
    field :name, :string
    field :species, :string
    field :bought_on, :utc_datetime
    field :bought_from, :string
  end
end
```

> To be true, the `bought_from` should be also a `belongs_to` relation, pointing to a table with
> contacts, like friends, other gardens, commercial nurseries.  But since there's so much more to
> come, let's keep it like this for the time being.

What does the `belongs_to/3` macro really do?  How does impact our physical database structure?
It would be nice if it was the system telling us, but in reality, it's us who need to tell the
system, by writing the corresponding migration.

A sentence from `h(Ecto.Schema.belongs_to/3)` contains the best clue: *"when you invoke this
macro, a field with the name of foreign key is automatically defined in the schema for you."*

### The initial migration

You came here after doing the more introductiory how-tos and tutorials, so you know how to set
up an Elixir project, how to configure your Ecto-DBMS connection, how to have Ecto create a
database, and you know how to handle migrations.

> Remember that Ecto does keep track of database changes through migrations, yet it is not
> particularly helpful when it comes to writing the migration corresponding to what we change in
> the schemas.  There has been discussion in the Ecto project about this, and the bottom line is
> that programmers need to know what they mean, and it's programmers who should tell Ecto, not
> the opposite way: we need to maintain both the schemas, and the migration files, and make sure
> they are consistent with each other.

So let's get to work and write our first migration, relative to moving from an empty database to
one with the above schema definitions.  We use the `ecto.gen.migration` rule to create a
boilerplate named migration, we call it `initial_migration`,

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

For the `belongs_to` line from the plants schema, we've written a `location_id` line in the
`plants` create table, referring to the `locations` table.  This implies we use its default
primary key, `id`.  Obviously, for the migration to work, the `create table(:locations)` must
precede the creation of the `plants` table, since we're referring the first from the second.

With this `initial_migration` in place, let's apply it, so that we can finally have a look at
the database tables.

```
mix ecto.migrate
```

If all is well, the output is just four `[info]` lines.

We have added quite a few files to our project, and altered others, let's do some housekeeping,

```
git add lib/botany/*.ex mix.lock priv config/config.exs
git commit -m "first migration"
```

### Looking at it from SQL

Fine, it took time, but we now have our updated schema, where we can check the meaning of
`belongs_to`.  To have a look, we need to connect directly to the database, not through Elixir.

Let's use the `psql` prompt (if you commonly use something else, you should know the commands
corresponding to what we show here).  Our database is called `botany_repo` and you know your user
and password.  From inside the `psql` prompt, give:

```
\dt
\d plants
\d locations
```

> En passant, have a look at the `schema_migrations` table and content, just to be aware of it.

What is relevant to us here is the `CONSTRAINT` block at the end of each table.  Ecto not only
created the columns, it also made our database aware of the meaning of the `location_id` in
`plants`, and that it impacts the `locations` table as well.

Since we're here in the database, let's create a few database records, so we save time in the
`iex` session, and can focus on navigation rather than data insertion.  More than a few in
reality, because we're out to navigating information with real data.  (If there's botanists among
you, please be assured we are on our way to do some proper work, I know this is *not* how to
model botanic data.)

```sql
insert into location (id, code, name) values (1, 'GH1', 'tropical greenhouse'),
    (2, 'GH2', 'mediterranean'), (3, 'B01', 'entrance front'),
    (4, 'B02', 'left of main path-1'), (5, 'B04', 'left of main path-2'),
    (6, 'B06', 'right of main path-1'), (7, 'B03', 'right of main path-2');
insert into plant (id, location_id, name, species) values
    ( 1,4,'2018.0002.1','Salvia fruticosa'),
    ( 2,2,'2018.0019.1','Origanum majorana'),
    ( 3,7,'2018.0025.1','Salvia officinalis'),
    ( 4,4,'2018.0026.1','Salvia fruticosa'),
    ( 5,2,'2018.0027.1','Salvia sclarea'),
    ( 6,1,'2018.0029.1','Musa sp.'),
    ( 7,1,'2018.0032.1','Heliconia sp.'),
    ( 8,1,'2018.0044.1','Heliconia sp.'),
    ( 9,1,'2018.0045.1','Heliconia sp.'),
    (10,1,'2018.0047.1','Musa sp.'),
    (11,1,'2018.0047.2','Musa sp.'),
    (12,1,'2018.0057.3','Musa sp.'),
    (13,6,'2018.0057.1','Zingiber sp.'),
    (14,3,'2018.0058.1','Calathea sp.'),
    (15,3,'2018.0063.1','Calathea sp.'),
    (16,3,'2018.0067.1','Origanum vulgare'),
    (17,3,'2018.0068.1','Origanum Majorana'),
    (18,2,'2018.0044.2','Salvia officinalis');
```

### Navigating, forward

This is nice, now we can switch to iex, which we start as `iex -S mix`, and have a look.

```iex
iex> Botany.Plant
Botany.Plant
iex> Botany.Plant |> Ecto.Query.first
#Ecto.Query<from p0 in Botany.Plant, order_by: [asc: p0.id], limit: 1>
```

We gave two instructions, we are not yet there.  With `Botany.Plant`, we mentioned our module,
which is just our module, *duh!*.  With `Botany.Plant |> Ecto.Query.first`, we built a query on
the schema in our module, and while this is the query we meant, we still did not hit the
database.

To hit the database, we have to evaluate the query, something we can do by `Botany.Plant |>
Ecto.Query.first |> Botany.Repo.all`.  The last pipe handles the query to `Botany.Repo.all`,
which evaluates the query and returns a list of structures, corresponding to the records
satisfying the query.  Or maybe better pipe the query through `Botany.Repo.one`, since
`Ecto.Query.first` is anyway guaranteed to contain no more than one records.

```iex
iex> Botany.Plant |> Ecto.Query.first |> Botany.Repo.one

09:54:00.985 [debug] QUERY OK source="plant" db=0.7ms
SELECT p0."id", p0."location_id", p0."name", p0."specie", p0."bought_on", p0."bought_from" FROM "plant" AS p0 ORDER BY p0."id" LIMIT 1 []
%Botany.Plant{
  __meta__: #Ecto.Schema.Metadata<:loaded, "plant">,
  bought_from: nil,
  bought_on: nil,
  id: 1,
  location: #Ecto.Association.NotLoaded<association :location is not loaded>,
  location_id: 8,
  name: "2018.0002.1",
  species: "Salvia fruticosa"
}
```

Now we are finally *almost* where we were aiming at.  We got everything from the `plants` table,
including obviously the `location_id` (hey, but isn't it funny? We added this field in the
`create table` block, but did not define it in the schema), and there's a curious `NotLoaded`
value in the `location` field (heck, think of it, we never saw a `location` field in the
`plants` database table).

Apart from the `NotLoaded` which we will explore shortly, all the above is precisely the effect
of that `belongs_to` macro in our schema and that `references` in the migration.

Let's refer back to the documentation for `belongs_to(name, queryable, opts \\ [])`.
In our case, `name` is `:location`, and `queryable` is `Botany.Location`.  **TODO**

### Preloading associations

Let's `preload` the relation! (and by the way let's type a few aliases for our tables.)

```iex
iex> alias Botany.Plant
Botany.Plant
iex> alias Botany.Location
Botany.Location
iex> Plant |> Ecto.Query.first |> Botany.Repo.one |> Botany.Repo.preload(:location)

10:05:47.533 [debug] QUERY OK source="plant" db=2.3ms queue=0.1ms
SELECT p0."id", p0."location_id", p0."name", p0."specie", p0."bought_on", p0."bought_from" FROM "plant" AS p0 ORDER BY p0."id" LIMIT 1 []

10:05:47.536 [debug] QUERY OK source="location" db=2.2ms queue=0.1ms
SELECT l0."id", l0."code", l0."name", l0."description", l0."id" FROM "location" AS l0 WHERE (l0."id" = $1) [8]
%Botany.Plant{
  __meta__: #Ecto.Schema.Metadata<:loaded, "plant">,
  bought_from: nil,
  bought_on: nil,
  id: 1,
  location: %Botany.Location{
    __meta__: #Ecto.Schema.Metadata<:loaded, "location">,
    code: "B05",
    description: nil,
    id: 8,
    name: "right of main path-2"
  },
  location_id: 8,
  name: "2018.0002.1",
  species: "Salvia fruticosa"
}
```

Now we hit the database twice (side effect was the two `SELECT` logging records on our
terminal), and we got a `%Location` structure within our `%Plant` structure, associated, as we
expected, to the `location` field.  Let's match this value to a `p1` variable, so we can reuse
it.

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

Whatever looks easier, or clearer to you in the context.  I like the first one better, because
we also assert that `p1` is a `Plant` structure.  In both cases, we're using the effects of the
`belongs_to` macro.

Consider the situation in which we had matched the `p1` variable to the expression without the
`preload` trailing pipe.  Never forget we are in an environment where objects are immutable, so
in this case `p1` would just be what you defined it to be, a match to a specific immutable
value.  If you later add the `preload` pipe to it, this would not alter your `p1` value, unless
you re-match `p1` to the new value, like this:

```iex
iex> p1 = p1 |> Botany.Repo.preload(:location)
```

It does no harm evaluating a `preload` on a preloaded field, it's an idempotent function.

### Navigating, backwards

Let's find an answer to a most obvious question: what plants are there at a given location?

Say we want to explore the content of Greenhouse 1, `GH1`.  Let's select it, match it to a
variable, and look up all the plants at that location.  (For ease of typing, let's first import
the `Ecto.Query` module.)

```iex
iex> import Ecto.Query
iex> gh1 = (from l in Location, where: l.code=="GH1") |> Botany.Repo.one
```

How do we do that… I would like to just type `gh1.plants`, doesn't it make sense, and I don't
mind if I first need to pipe through a `preload`… But, as of now, all I can think of is to type
a complete query!  After all, `gh1` is just a value, a structure, it has no `plants` field, and
the module does not define how to compute that.

```iex
iex> q = from p in Plant, where: p.location_id==^gh1.id
iex> q |> Botany.Repo.all
iex> q |> Botany.Repo.all |> length
```

With what we have, we can go up the links, by this I mean that we can get the `location` from a
plant, but Ecto can help us move in the other direction too, as we're trying to do here.  This is
precisely what the macro `has_many` offers us.  Open the `location.ex` file and add a single line
in the schema.

```iex
defmodule Botany.Location do
  use Ecto.Schema

  schema "location" do
    has_many :plants, Botany.Plant  # backward link
    field :code, :string
    field :name, :string
    field :description, :string
  end
end
```

`recompile`, and reload the structure for location `gh1`.  You will notice, it holds the new
`plants` field, indeed as expected in need of `preload`.  You know how to do that, and you will
get a nicely populated `gh1.plants` field, with a list of `%Plant` structures.  You should be
surprised, or maybe not, for we did not need any migration.

The `belongs_to` macro defines a field in the schema containing it, and implies the presence of
a foreign key in the database table corresponding to our schema, pointing to the `queryable`
given as second argument.  The `has_many` macro also defines a field in the schema containing
it, but it implies the presence of a foreign key in the target table, pointing back to the
database table corresponding to our schema.

Have fun with the project and the data, explore, learn, understand, and take a well deserved
pause: There's much more to come, and it's not going to be easy.

## Life is complex, and information scientists think they can model it
*day 2*

You must have heard of those funny names biologists use, like they say *Canis lupus familiaris*
when all they mean is "dog", or when they confuse you with *Origanum majorana* (is it oregano,
or marjoram?) and what is the reason that common oregano should be considered vulgar? Also, if
you have been in the Tropics, you surely noticed how easy it is to confuse a banana plant with
larger flowerless heliconia, and with other plants used in *tamales*, which provide no fruit
nor carry any particularly showy flowers.  The answer is in **taxonomy** : common oregano and
marjoram both belong to the *Origanum* genus, while bananas, heliconias, and bihao belong to
the *Zingiberales* order, and all are vascular plants, or *Tracheophyta*.

If you think we chose a too complex example, well, we are using this example precisely because
it's a complex one, coming from real life, and not the rather tedious and far too simplistic
*Library* example.  We will not need to invent stories here, and you will be able to find
background information, to make sense of the complexity we are modelling, by checking reference
sources, like the Wikipedia, or sites like https://atlasoflife.org.au/, or
http://tropicos.org/.  Enjoy reading, and enjoy nature!  If you really need Library science, we
will use some here too.

Oh, and back to *Zingiberales*, Ginger —*Zingiber*— is also one of them.

### Modelling taxonomic information

Modelling taxonomic information is a typical example where we need self-relations.  Taxonomists
speak of a `Taxon`, which is a concept that encompasses Divisions, Orders, Families, as well as
several more.  Each of these names identifies a `Rank`, and a `Taxon` has a rank (or, in Ecto
terms, it `belongs_to` a rank), and also belongs to one taxon at a higher rank.  A `Rank` has
nothing more than a name.  We could add an integer value to represent its depth in the taxonomy
tree of life, but let's forget about that for the time being.

The above mentioned taxa ('taxa' is the Greek plural form for taxon) are so organized:

```
Tracheophyta
 |--Zingiberales
 |  |--Musaceae
 |  |  |--Musa  (bananas)
 |  |
 |  |--Zingiberaceae
 |  |  |--Zingiber  (ginger)
 |  |
 |  |--Heliconiaceae
 |  |  |--Heliconia  (heliconias)
 |  |
 |  |--Marantaceae
 |     |--Calathea  (bihao)
 |
 |--Lamiales
    |--Lamiaceae
       |--Origanum
       |  |--Origanum vulgare
       |  |--Origanum majorana
       |
       |--Salvia
          |--Salvia fruticosa
          |--Salvia oficinalis
          |--Salvia sclarea
```

Here we have one "Division", two "Orders", five "Families" and then genera and species.  To keep
things as simple as possible, but still meaningful, we will work with a real life collection,
but limited to the above taxa.

### New schema with self-reference

As above, we first write the schemas, then the migration, then run it.  The two tables
corresponding to the two above concepts are not complicated after all, and allow us represent
the above information.

Question is: how do we write the migration for the self-reference in `Botany.Taxon`? As you
recall, we could not use a schema which had not yet been defined, and here we're referring to
one while we're busy defining it, and not quite yet done.

To `mix`, it makes no difference what we do first, whether the schema modules, or request
creation of the boilerplate migration.  Let's this time generate the migration first.

```bash
mix ecto.gen.migration create_taxonomy
```

Now create the two files `botany/rank.ex` and `botany/taxon.ex`, with the content as discussed:

```iex
defmodule Botany.Rank do
  use Ecto.Schema

  schema "rank" do
    field :name, :string
  end
end

defmodule Botany.Taxon do
  use Ecto.Schema

  schema "taxon" do
    field :epithet, :string
    field :authorship, :string
    belongs_to :parent, Botany.Taxon
    belongs_to :rank, Botany.Rank
  end
end
```

(The authorship field is a hard requirement by botanists.  Without that, they'll never believe
we're serious about their subject.  Also, we leave the table name in its singular form, because
the correct Greek plural looks so weird.)

And let's write a wild guess for the migration, as if all would just work.

```iex
defmodule Botany.Repo.Migrations.CreateTaxonomy do
  use Ecto.Migration

  def change do
    create table(:ranks) do
      add :name, :string
    end

    create table(:taxon) do
      add :epithet, :string
      add :authorship, :string
      add :rank_id, references(:ranks)
      add :parent_id, references(:taxon)
    end
  end
end
```

Let's see what error we get from running this migration:

```bash
mix ecto.migrate
```

Wow, really, just the four `[info]` lines? No errors? Since neither you nor I believe it, let's
check in the SQL shell: go back to it, and give the command `\d taxon`.

```
Foreign-key constraints:
    "taxon_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES taxon(id)
    "taxon_rank_id_fkey" FOREIGN KEY (rank_id) REFERENCES ranks(id)
```

Neat, cool, nice.

Since we're here in the SQL shell, and since as said it is not our goal here learning how to
insert data, but how to navigate it, let's add some ranks and taxa, from the same above example:

```sql
insert into rank (id,name) values (1,'divisio'), (2,'ordo'), (3,'familia'), (7,'genus'), (8,'species');
insert into taxon (id,rank_id,epithet,authorship) values
    (1,1,'Tracheophyta','Sinnott, ex Cavalier-Smith');
insert into taxon (id,rank_id,epithet,authorship,parent_id) values
    (2,2,'Zingiberales','Grieseb.',1),
    (3,3,'Musaceae','Juss.',2),
    (4,7,'Musa','L.',3),
    (5,3,'Zingiberaceae','Martinov',2),
    (6,3,'Marantaceae','R.Br.',2),
    (7,7,'Zingiber','Mill.',6),
    (8,3,'Heliconiaceae','Vines',2),
    (9,7,'Heliconia','L.',8),
    (10,2,'Lamiales','Bromhead',1),
    (11,3,'Lamiaceae','Martinov',10),
    (12,7,'Origanum','L.',11),
    (13,8,'vulgare','L.',12),
    (14,8,'majorana','L.',12),
    (15,7,'Salvia','L.',11),
    (16,8,'fruticosa','Mill.',15),
    (17,8,'oficinalis','L.',15),
    (18,8,'sclarea','L.',15),
    (19,7,'Calathea','G.Mey.',6);
```

It's probably useful if we stop here again, and do some data navigation, like we write a query
for the taxon named *Salvia*, match the query to a variable `q`, and then evaluate `q` and
extract the information for the taxon rank, its epithet, and its parent taxon epithet.

A piece of cake, or isn't it? (remember to `recompile` when necessary, and remember that values
are immutable, and that reloading a module does not impact existing values.)

```
q = from t in Taxon, where: t.epithet=="Salvia"
```

Next part is evaluation, and preloading fields:
```
matched_taxon = q |> Botany.Repo.one |> Botany.Repo.preload(:rank) |> Botany.Repo.preload(:parent)
```

Then there's the matching part, which looks like this, for the rank name:

```
%Taxon{rank: %Rank{name: rank_name}} = matched_taxon
```

or, if you only need one field, you can extract it from the other end:

```
rank_name = matched_taxon.rank.name
```

### Collecting taxon children

We should know how to do this part, adding a `has_many` for a new `children` field.  It's mostly
a repetition of what we did before with plants at a location, with the important difference that
the self linking key is not called as the collection name (with `plants`, it was `location_id`.
Here it would be `taxon_id`, which is obviously not the case), but it is `parent_id`.

The field to add to the `taxon` schema is:

```
    has_many :children, Botany.Taxon, foreign_key: :parent_id  # backward link
```

And as before, there's no impact on the database, just `recompile`, execute the same query,
taking care to `preload(:children)`.

Time for a bit of taxonomic navigation?  Experiment on your own, moving up the tree (match the
`.parent`) and then down (match the `.children` and choose one).  For example from Calathea to
Musa:

```iex
import Ecto.Query
q = from t in Botany.Taxon, where: t.epithet=="Calathea"
origin = q |> Botany.Repo.one |> Botany.Repo.preload(:parent)
family1 = origin.parent |> Botany.Repo.preload(:parent)
ordo = family1.parent |> Botany.Repo.preload(:children)
family2 = Enum.find(ordo.children, fn x -> x.epithet=="Musaceae" end) |> Botany.Repo.preload(:children)
target = Enum.find(family2.children, fn x -> x.epithet=="Musa" end) |> Botany.Repo.preload(:children)
```

How would you do the same, but using pattern matching?

### Writing a second self referring migration

As said in the introduction, we're doing this example because it's a complex one.  Now one extra
complexity comes from scientific advances, where new plant species are discovered and described,
or some new genetic studies suggest a complete reorganization of previous taxonomic structures.
This is complex enough, but it gets worse when they add the requirement that old names must be
kept, in fact unsuprisingly as you cannot require that all literature since Linneus gets
rewritten every 10 or so years, in the light of new science.

The above paragraph introduces the concept of botanic synonyms.

What does it imply to our case?

We can represent synonymy among taxa, where each taxon either links to its accepted taxon, or
the link is `NULL`, meaning that the taxon is itself an accepted name.  (Actually, things are
much more complex than this, for the concept of "accepted taxon" is an opinion, but let's do as
if life were easy for this one time once.)

In a way, this is also some sort of `belongs_to`, as when a taxon S points to a taxon A as its
accepted name, it is saying that it belongs to the set of synonyms for A.  The back link is just
as obvious by now.

```
    belongs_to :accepted, Botany.Taxon
    has_many :synonyms, Botany.Taxon, foreign_key: :accepted_id  # backward link
```

Let's not forget the migration, which is now of a different type, since we're altering an
existing table:

```
mix ecto.gen.migration adding_synonymies
```

```
defmodule Botany.Repo.Migrations.AddingSynonymies do
  use Ecto.Migration

  def change do
    alter table("taxon") do
      add :accepted_id, references(:taxon)
    end
  end
end
```

The more alert reader noticed this from the start: migrations closely describe the database
table and fields, using terms very recognizable from a SQL point of view. The two `belongs_to`
and `has_many` macros on the other hand add fields to our schemas, and use the effects of the
migrations.

## A more proper way to organize a botanical collection
*day 3*

### The garden as a library: the Accession (data migration - question)

When a gardener acquires a plant, they seldom acquire just one for each species, it is often in
batches, where a batch contains several groups of plants from the same source, at the same
time, of the same species, and then these plants may end in different locations in the garden.
To make sure that the physical plants are kept together conceptually, we introduce a library
science concept into our botanical collection: an "Accession", grouping the plants sharing the
same core information.  This allow us keeping together plants which belong together.

In our above sample data, we had a `Plant.name` field, composed of a year, a sequential number,
and a second sequential number.  By now you may have guessed: the first two components were
indeed the Accession code, while the trailing number identified the plant within the accession.

All common information for all plants in the same accession, we just move that to the
Accession.

Let's summarize this, showing the somewhat simplified `Botany.Plant` module, and the new
`Botany.Accession` module:

```iex
defmodule Botany.Accession do
  use Ecto.Schema

  schema "accession" do
    field :code, :string
    field :species, :string
    field :orig_quantity, :integer
    field :bought_on, :utc_datetime
    field :bought_from, :string
  end
end

defmodule Botany.Plant do
  use Ecto.Schema

  schema "plant" do
    belongs_to :location, Botany.Location
    belongs_to :accession, Botany.Accession
    field :code, :string
    field :quantity, :integer
  end
end
```

But if we do this in one shot, we would drop all the information we have in the `name` and
`species` columns of the `plants` table.  On the other hand, we do intend to drop those columns
in the end.

The point to make here is that we have two types of migrations, one is the schema migration,
which we have seen how to handle, but how to handle data migration, in particular when across
relations?  This is what we will walk through in the next section.

### A two steps data migration

Let's begin with the more simple case: `Plant.name`.  Migrating it means splitting the
information among the plant record and its corresponding accession.  What we do here is to
first add tables and columns to the database, make sure that the changes are reflected in the
database, leave temporarily in place all the old structure, which we use while migrating the
data, finally drop the now obsolete columns.

Such a migration cannot be automatically reverted, meaning we do not use the simplified form
`change` but write two separate functions `up` (for applying the migration) and `down` (for
reverting it).

```
  def up do
    create table(:accession) do
      add :code, :string
      add :species, :string
      add :orig_quantity, :integer
      add :bought_on, :utc_datetime
      add :bought_from, :string
    end

    alter table(:plant) do
      add :code, :string
      add :accession_id, references(:accession)
    end

    flush()

    from("plant", select: [:id, :bought_on, :bought_from, :name, :species, :accession_id, :code]) |>
      Botany.Repo.all |>
      Enum.each( TODO <%%> FILL IN THE BLANKS )

    alter table(:plant) do
      remove :name
      remove :species
    end
  end
```

As said: adding tables and columns, flushing the changes to the database, migrating the data
—one record at a time—, cleaning up the obsolete structure.

And the function which we left as TODO, might look like this.

```
    import Ecto.Query
    split_plant_create_accession = fn(plant) ->
      [_, acc_code, plt_code] = Regex.run(~r{(.*)\.([^\.]*)}, plant.name)
      query = from(a in "accession", select: [:id, :code], where: a.code==^acc_code)
      accession = case (query |> Botany.Repo.one()) do
                    nil -> (accession = %{id:         plant.id,
                                         bought_on:   plant.bought_on,
                                         bought_from: plant.bought_from,
                                         code:        acc_code,
                                         species:     plant.species,
                                         };
                      Botany.Repo.insert_all("accession", [accession]);
                      accession)
                    x -> x
                  end
      from(p in "plant", where: p.id==^plant.id, select: p.id) |>
        Botany.Repo.update_all(set: [accession_id: accession.id, code: plt_code])
    end
```

What it does is quite linear:

- it accepts a structure, as `plant` (we might pattern-match it, for clarity),
- splits `plant.name` in accession code and plant code,
- defines a query on the `"accession"` table, based on the value of the accession code,
- matches `accession` to either the result of the query, or to a new structure,
- defines a query on the `"plant"` table, and finally
- handles the query to the `update_all` function, setting the new fields for `"plant"`.

There is one possibly subtle detail here which should not go unnoticed.  In the description and
in the code above we never used our modules `Botany.Plant` nor `Botany.Accession`.  We worked
the whole migration with schemaless queries, be they `select`, `insert` or `update`, straight
on the database.

Before applying a migration, the tables have a form, and after the migration, they have an
other form.  At each moment in the history of our program, its modules match a database
definition.  If we're looking at an older migration, chances are that the current table has an
different definition.  It might even have been dropped altogether.

Since modules reflect the latest situation, they cannot be relied upon while reconstructing
history, as we do in migrations.

We just showed the `up` migration, and we also need its `down` equivalent.  The structure is
similar to the `up` migration, adding columns, flushing, migrating data, removing columns and
table in the right order.  **any volunteer**?

```
  def down do
    alter table(:plant) do
      add :name, :string
      add :species, :string
    end

    flush()

    # we should migrate data back

    alter table(:plant) do
      remove :code
      remove :accession_id
    end

    drop table(:accession)
  end
```

### Multi-tables search and association

As mentioned above, before this migration our `Plant` also has a `species` field, no more than
a `:string`.  This is a very rude way to link a plant to its taxon.  With the above migration
we moved the `species` field to the new `Accession` module, but did not translate it into a
proper link to the `Taxon`.  Let's do it now.

This migration amounts to replacing the `Accession.species` string field with an association to
the `taxon` table.  As in the previous migration, we add one column and drop an other.  Since
dropping a column does not indicate its previous definition, also this migration is not
automatically reversible, and we need to define both the `up` and the `down` functions.

```
  def up do
    alter table(:accession) do
      add :taxon_id, references(:taxon)
    end

    flush()

    ## do something

    alter table(:accession) do
      remove :species
    end
  end

  def down do
    alter table(:accession) do
      add :species, :string
    end

    flush()

    # do the opposite of something

    alter table(:accession) do
      remove :taxon_id
    end
  end
```

```
  schema "accession" do
    field :code, :string
    belongs_to :taxon, Botany.Taxon
    has_many :plants, Botany.Plant
    field :orig_quantity, :integer
    field :bought_on, :utc_datetime
    field :bought_from, :string
  end
```

### Verifications (many-to-many)

But what if an other taxonomist has a different opinion? This happens regularly, and one
generally notes all opinions, which in botany jargon are called "Verifications", in an
intermediate table that defines a many-to-many relation, between accessions and taxa.

We remove the taxon_id foreign key from accessions and move it into verifications.

```iex
defmodule Botany.Verification do
  use Ecto.Schema

  schema "verification" do
    belongs_to :accession, Botany.Accession
    belongs_to :taxon, Botany.Taxon
    field :verifier, :string
  end
end

defmodule Botany.Accession do
  use Ecto.Schema

  schema "accession" do
    field :code, :string
    field :orig_quantity, :integer
    field :bought_on, :utc_datetime
    field :bought_from, :string
  end
end
```

### Contacts management (one-to-one)

finally, `one_to_one`: contacts, sources, verifiers, gardners, visitors.
