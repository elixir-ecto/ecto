# Composable transactions with Multi

Ecto relies on database transactions when multiple operations must be performed atomically. The most common example used for transactions are bank transfers between two people:

```elixir
Repo.transaction(fn ->
  mary_update =
    from Account,
      where: [id: ^mary.id],
      update: [inc: [balance: +10]]

  {1, _} = Repo.update_all(mary_update)

  john_update =
    from Account,
      where: [id: ^john.id],
      update: [inc: [balance: -10]]

  {1, _} = Repo.update_all(john_update)
end)
```

In Ecto, transactions can be performed via the `Repo.transaction` function. When we expect both operations to succeed, as above, transactions are quite straight-forward. However, transactions get more complicated if we need to check the status of each operation along the way:

```elixir
Repo.transaction(fn ->
  mary_update =
    from Account,
      where: [id: ^mary.id],
      update: [inc: [balance: +10]]

  case Repo.update_all mary_update do
    {1, _} ->
      john_update =
        from Account,
          where: [id: ^john.id],
          update: [inc: [balance: -10]]

      case Repo.update_all john_update do
        {1, _} -> {mary, john}
        {_, _} -> Repo.rollback({:failed_transfer, john})
      end

    {_, _} ->
      Repo.rollback({:failed_transfer, mary})
  end
end)
```

Transactions in Ecto can also be nested arbitrarily. For example, imagine the transaction above is moved into its own function that receives both accounts, defined as `transfer_money(mary, john, 10)`, and besides transferring money we also want to log the transfer:

```elixir
Repo.transaction(fn ->
  case transfer_money(mary, john, 10) do
    {:ok, {mary, john}} ->
      transfer = %Transfer{
        from: mary.id,
        to: john.id,
        amount: 10
      }

      Repo.insert!(transfer)

    {:error, error} ->
      Repo.rollback(error)
  end
end)
```

The snippet above starts a transaction and then calls `transfer_money/3` that also runs in a transaction. In the case of multiple transactions, they are all flattened, which means a failure in an inner transaction causes the outer transaction to also fail. That's why matching and rolling back on `{:error, error}` is important.

While nesting transactions can improve the code readability by breaking large transactions into multiple smaller transactions, there is still a lot of boilerplate involved in handling the success and failure scenarios. Furthermore, composition is quite limited, as all operations must still be performed inside transaction blocks.

A more declarative approach when working with transactions would be to define all operations we want to perform in a transaction decoupled from the transaction execution. This way we would be able to compose transactions operations without worrying about its execution context or about each individual success/failure scenario. That's exactly what `Ecto.Multi` allows us to do.

## Composing with data structures

Let's rewrite the snippets above using `Ecto.Multi`. The first snippet that transfers money between Mary and John can be rewritten to:

```elixir
mary_update =
  from Account,
    where: [id: ^mary.id],
    update: [inc: [balance: +10]]

john_update =
  from Account,
    where: [id: ^john.id],
    update: [inc: [balance: -10]]

Ecto.Multi.new()
|> Ecto.Multi.update_all(:mary, mary_update)
|> Ecto.Multi.update_all(:john, john_update)
```

`Ecto.Multi` is a data structure that defines multiple operations that must be performed together, without worrying about when they will be executed. `Ecto.Multi` mirrors most of the `Ecto.Repo` API, with the difference that each operation must be explicitly named. In the example above, we have defined two update operations, named `:mary` and `:john`. As we will see later, the names are important when handling the transaction results.

Since `Ecto.Multi` is just a data structure, we can pass it as argument to other functions, as well as return it. Assuming the multi above is moved into its own function, defined as `transfer_money(mary, john, value)`,  we can add a new operation to the multi that logs the transfer as follows:

```elixir
transfer = %Transfer{
  from: mary.id,
  to: john.id,
  amount: 10
}

transfer_money(mary, john, 10)
|> Ecto.Multi.insert(:transfer, transfer)
```

This is considerably simpler than the nested transaction approach we have seen earlier. Once all operations are defined in the multi, we can finally call `Repo.transaction`, this time passing the multi:

```elixir
transfer = %Transfer{
  from: mary.id,
  to: john.id,
  amount: 10
}

transfer_money(mary, john, 10)
|> Ecto.Multi.insert(:transfer, transfer)
|> Repo.transaction()
|> case do
  {:ok, %{transfer: transfer}} ->
    # Handle success case
  {:error, name, value, changes_so_far} ->
    # Handle failure case
end
```

If all operations in the multi succeed, it returns `{:ok, map}` where the map contains the name of all operations as keys and their success value. If any operation in the multi fails, the transaction is rolled back and `Repo.transaction` returns `{:error, name, value, changes_so_far}`, where `name` is the name of the failed operation, `value` is the failure value and `changes_so_far` is a map of the previously successful multi operations that have been rolled back due to the failure.

In other words, `Ecto.Multi` takes care of all the flow control boilerplate while decoupling the transaction definition from its execution, allowing us to compose operations as needed.

## Dependent values

Besides operations such as `insert`, `update` and `delete`, `Ecto.Multi` also provides functions for handling more complex scenarios. For example, `prepend` and `append` can be used to merge multis together. And more generally, the functions `Ecto.Multi.run/3` and `Ecto.Multi.run/5` can be used to define any operation that depends on the results of a previous multi operation. In addition, `Ecto.Multi` also gives us `put` and `inspect`, which allow us to dynamically update and inspect changes.

Let's study a more practical example. In [Constraints and Upserts](Constraints and Upserts.md), we want to modify a post while possibly giving it a list of tags as a string separated by commas. At the end of the guide, we present a solution that inserts any missing tag and then fetches all of them using only two queries:

```elixir
defmodule MyApp.Post do
  use Ecto.Schema

  # Schema is the same
  schema "posts" do
    field :title
    field :body
    many_to_many :tags, MyApp.Tag,
      join_through: "posts_tags",
      on_replace: :delete
    timestamps()
  end

  # Changeset is the same
  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [:title, :body])
    |> Ecto.Changeset.put_assoc(:tags, parse_tags(params))
  end

  # Parse tags has slightly changed
  defp parse_tags(params)  do
    (params["tags"] || "")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(& &1 == "")
    |> insert_and_get_all()
  end

  defp insert_and_get_all([]) do
    []
  end

  defp insert_and_get_all(names) do
    timestamp =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.truncate(:second)

    maps =
      Enum.map(names, &%{
        name: &1,
        inserted_at: timestamp,
        updated_at: timestamp
      })

    Repo.insert_all(MyApp.Tag, maps, on_conflict: :nothing)

    Repo.all(from t in MyApp.Tag, where: t.name in ^names)
  end
end
```

While `insert_and_get_all/1` is idempotent, allowing us to run it multiple times and get the same result back, it does not run inside a transaction, so any failure while attempting to modify the parent post struct would end-up creating tags that have no posts associated to them.

Let's fix the problem above by introducing using `Ecto.Multi`. Let's start by splitting the logic into both `Post` and `Tag` modules and keeping it free from side-effects such as database operations:

```elixir
defmodule MyApp.Post do
  use Ecto.Schema

  schema "posts" do
    field :title
    field :body
    many_to_many :tags, MyApp.Tag,
      join_through: "posts_tags",
      on_replace: :delete
    timestamps()
  end

  def changeset(struct, tags, params) do
    struct
    |> Ecto.Changeset.cast(params, [:title, :body])
    |> Ecto.Changeset.put_assoc(:tags, tags)
  end
end

defmodule MyApp.Tag do
  use Ecto.Schema

  schema "tags" do
    field :name
    timestamps()
  end

  def parse(tags) do
    (tags || "")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(& &1 == "")
  end
end
```

Now, whenever we need to introduce a post with tags, we can create a multi that wraps all operations and the repository access:

```elixir
alias MyApp.Tag

def insert_or_update_post_with_tags(post, params) do
  Ecto.Multi.new()
  |> Ecto.Multi.run(:tags, fn _repo, changes ->
    insert_and_get_all_tags(changes, params)
  end)
  |> Ecto.Multi.run(:post, fn _repo, changes ->
    insert_or_update_post(changes, post, params)
  end)
  |> Repo.transaction()
end

defp insert_and_get_all_tags(_changes, params) do
  case MyApp.Tag.parse(params["tags"]) do
    [] ->
      {:ok, []}

    names ->
      timestamp =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.truncate(:second)

      maps =
        Enum.map(names, &%{
          name: &1,
          inserted_at: timestamp,
          updated_at: timestamp
        })

      Repo.insert_all(Tag, maps, on_conflict: :nothing)

      query = from t in Tag, where: t.name in ^names

      {:ok, Repo.all(query)}
  end
end

defp insert_or_update_post(%{tags: tags}, post, params) do
  post
  |> MyApp.Post.changeset(tags, params)
  |> Repo.insert_or_update()
end
```

In the example above we have used `Ecto.Multi.run/3` twice, albeit for two different reasons.

  1. In `Ecto.Multi.run(:tags, ...)`, we used `run/3` because we need to perform both `insert_all` and `all` operations, and while the multi exposes `Ecto.Multi.insert_all/4`, it does not have an equivalent to `Ecto.Repo.all`. Whenever we need to perform a repository operation that is not supported by `Ecto.Multi`, we can always fallback to `run/3` or `run/5`.

  2. In `Ecto.Multi.run(:post, ...)`, we used `run/3` because we need to access the value of a previous multi operation. The function given to `run/3` receives, as second argument, a map with the results of the operations performed so far. To grab the tags returned in the previous step, we simply pattern match on `%{tags: tags}` on `insert_or_update_post`.

> Note: The first argument received by the function given to `run/3` is the repo in which the transaction is executing.

While `run/3` is very handy when we need to go beyond the functionalities provided natively by `Ecto.Multi`, it has the downside that operations defined with `Ecto.Multi.run/3` are opaque and therefore they cannot be inspected by functions such as `Ecto.Multi.to_list/1`. Still, `Ecto.Multi` allows us to greatly simplify control flow logic and remove boilerplate when working with transactions.
