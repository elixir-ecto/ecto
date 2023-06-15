# Basic CRUD

In this document, "Internal data" represents data or logic hardcoded into your Elixir code. "External data" means data that comes from the user via forms, APIs, and often need to be normalized, pruned, and validated via Ecto.Changeset.

## Fetching records
{: .col-2}

### Single record

#### Fetching record by ID

```elixir
Repo.get(Movie, 1)
```

#### Fetching record by attributes

```elixir
Repo.get_by(Movie, title: "Ready Player One")
```

#### Fetching the first record

```elixir
Movie |> Ecto.Query.first() |> Repo.one()
```

#### Fetching the last record

```elixir
Movie |> Ecto.Query.last() |> Repo.one()
```

#### Use `!` to raise if none is found

```elixir
Repo.get!(Movie, 1)
Repo.get_by!(Movie, title: "Ready Player One")
Movie |> Ecto.Query.first() |> Repo.one!()
```

### Multiple records

#### Fetch all at once

```elixir
Movie |> Repo.all()
```

#### Stream all

```elixir
Movie |> Repo.stream() |> Enum.each(fn record -> ... end)
```

#### Check at least one exists?

```elixir
Movie |> Repo.exists?()
```

## Querying records
{: .col-2}

### Keyword-based queries

#### Bindingless queries

```elixir
query =
  from Movie,
  where: [title: "Ready Player One"],
  select: [:title, :tagline]
Repo.all(query)
```

#### Bindings in queries

```elixir
query =
  from m in Movie,
  where: m.title == "Ready Player One",
  select: [m.title, m.tagline]
Repo.all(query)
```

### Interpolation with `^`

```elixir
title = "Ready Player One"
query =
  from m in Movie,
  where: m.title == ^title,
  select: [m.title, m.tagline]
Repo.all(query)
```

### Pipe-based queries

```elixir
Movie
|> where([m], m.title == "Ready Player One")
|> select([m], {m.title, m.tagline})
|> Repo.all
```

## Inserting records
{: .col-2}

### Single record

#### Using internal data

```elixir
%Person{name: "Bob"}
|> Repo.insert()
```

#### Using external data

```elixir
# Params represent data from a form, API, CLI, etc
params = %{"name" => "Bob"}

%Person{}
|> Ecto.Changeset.cast(params, [:name])
|> Repo.insert()
```

### Multiple records

```elixir
data = [%{name: "Bob"}, %{name: "Alice"}]
Repo.insert_all(Person, data)
```

## Updating records
{: .col-2}

### Single record

#### Using internal data

```elixir
person =
  Person
  |> Ecto.Query.first()
  |> Repo.one!()

changeset = change(person, %{age: 29})
Repo.update(changeset)
```

#### Using external data

```elixir
# Params represent data from a form, API, CLI, etc
params = %{"age" => "29"}

person =
  Person
  |> Ecto.Query.first()
  |> Repo.one!()

changeset = cast(person, params, [:age])
Repo.update(changeset)
```

### Multiple records (using queries)

```elixir
Repo.update_all(Person, set: [age: 29])
```

## Deleting records
{: .col-2}

### Single record

```elixir
person = Repo.get!(Person, 1)
Repo.delete(person)
```

### Multiple records (using queries)

```elixir
Repo.delete_all(Person)
```