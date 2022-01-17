# Replicas and dynamic repositories

When applications reach a certain scale, a single database may not be enough to sustain the required throughput. In such scenarios, it is very common to introduce read replicas: all write operations are sent to the primary database and most of the read operations are performed against the replicas. The credentials of the primary and replica databases are typically known upfront by the time the code is compiled.

In other cases, you may need a single Ecto repository to interact with different database instances which are not known upfront. For instance, you may need to communicate with hundreds of databases very sporadically, so instead of opening up a connection to each of those hundreds of databases when your application starts, you want to quickly start a connection, perform some queries, and then shut down, while still leveraging Ecto's APIs as a whole.

This guide will cover how to tackle both approaches.

## Primary and Replicas

Since the credentials of the primary and replicas databases are known upfront, adding support for primary and replica databases in your Ecto application is relatively straightforward. Imagine you have a `MyApp.Repo` and you want to add four read replicas. This could be done in three steps.

First, define the primary and replicas repositories in `lib/my_app/repo.ex`:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  @replicas [
    MyApp.Repo.Replica1,
    MyApp.Repo.Replica2,
    MyApp.Repo.Replica3,
    MyApp.Repo.Replica4
  ]

  def replica do
    Enum.random(@replicas)
  end

  for repo <- @replicas do
    defmodule repo do
      use Ecto.Repo,
        otp_app: :my_app,
        adapter: Ecto.Adapters.Postgres,
        read_only: true
    end
  end
end
```

The code above defines a regular `MyApp.Repo` and four replicas, called `MyApp.Repo.Replica1` up to `MyApp.Repo.Replica4`. We pass the `:read_only` option to the replica repositories, so operations such as `insert`, `update` and friends are not made accessible. We also define a function called `replica` with the purpose of returning a random replica.

Next we need to make sure both primary and replicas are configured properly in your `config/config.exs` files. In development and test, you can likely use the same database credentials for all repositories, all pointing to the same database address:

```elixir
replicas = [
  MyApp.Repo,
  MyApp.Repo.Replica1,
  MyApp.Repo.Replica2,
  MyApp.Repo.Replica3,
  MyApp.Repo.Replica4
]

for repo <- replicas do
  config :my_app, repo,
    username: "postgres",
    password: "postgres",
    database: "my_app_prod",
    hostname: "localhost",
    pool_size: 10
end
```

In production, you want each database to connect to a different hostname:

```elixir
repos = %{
  MyApp.Repo => "prod-primary",
  MyApp.Repo.Replica1 => "prod-replica-1",
  MyApp.Repo.Replica2 => "prod-replica-2",
  MyApp.Repo.Replica3 => "prod-replica-3",
  MyApp.Repo.Replica4 => "prod-replica-4"
}

for {repo, hostname} <- repos do
  config :my_app, repo,
    username: "postgres",
    password: "postgres",
    database: "my_app_prod",
    hostname: hostname,
    pool_size: 10
end
```

Finally, make sure to start all repositories in your supervision tree:

```elixir
children = [
  MyApp.Repo,
  MyApp.Repo.Replica1,
  MyApp.Repo.Replica2,
  MyApp.Repo.Replica3,
  MyApp.Repo.Replica4
]
```

Now that all repositories are configured, we can safely use them in your application code. Every time you are performing a read operation, you can call the `replica/0` function that we have added to return a random replica we will send the query to:

```elixir
MyApp.Repo.replica().all(query)
```

And now you are ready to work with primary and replicas, no hacks or complex dependencies required!

## Testing replicas

While all of the work we have done so far should fully work in development and production, it may not be enough for tests. Most developers testing Ecto applications are using a sandbox, such as the [Ecto SQL Sandbox](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html).

When using a sandbox, each of your tests run in an isolated and independent transaction. Once the test is done, the transaction is rolled back. Which means we can trivially revert all of the changes done in a test in a very performant way.

Unfortunately, even if you configure your primary and replicas to have the same credentials and point to the same hostname, each Ecto repository will open up their own pool of database connections. This means that, once you move to a primary + replicas setup, a simple test like this one won't pass:

```elixir
user = Repo.insert!(%User{name: "jane doe"})
assert Repo.replica().get!(User, user.id)
```

That's because `Repo.insert!` will write to one database connection and the repository returned by `Repo.replica()` will perform the read in another connection. Since the write is done in a transaction, its contents won't be available to other connections until the transaction commits, which will never happen for test connections.

There are two options to tackle this problem: one is to change replicas and the other is to use dynamic repos.

### A custom `replica` definition

One simple solution to the problem above is to use a custom `replica` implementation during tests that always return the primary repository, like this:

```elixir
if Mix.env() == :test do
  def replica, do: __MODULE__
else
  def replica, do: Enum.random(@replicas)
end
```

Now during tests, the replica will always return the repository primary repository itself. While this approach works fine, it has the downside that, if you accidentally invoke a write function in a replica, the test will pass, since the `replica` function is returning the primary repo, while the code will fail in production.

### Using `:default_dynamic_repo`

Another approach to testing is to set the `:default_dynamic_repo` option when defining the repository. Let's see what we mean by that.

When you list a repository in your supervision tree, such as `MyApp.Repo`, behind the scenes it will start a supervision tree with a process named `MyApp.Repo`. By default, the process has the same name as the repository module itself. Now every time you invoke a function in `MyApp.Repo`, such as `MyApp.Repo.insert/2`, Ecto will use the connection pool from the process named `MyApp.Repo`.

From v3.0, Ecto has the ability to start multiple processes from the same repository. The only requirement is that they must have different process names, like this:

```elixir
children = [
  MyApp.Repo,
  {MyApp.Repo, name: :another_instance_of_repo}
]
```

While the particular example doesn't make much sense (we will cover an actual use case for this feature next), the idea is that now you have two repositories running: one is named `MyApp.Repo` and the other one is named `:another_instance_of_repo`. Each of those processes have their own connection pool. You can tell Ecto which process you want to use in your repo operations by calling:

```elixir
MyApp.Repo.put_dynamic_repo(MyApp.Repo)
MyApp.Repo.put_dynamic_repo(:another_instance_of_repo)
```

Once you call `MyApp.Repo.put_dynamic_repo(name)`, all invocations made on `MyApp.Repo` will use the connection pool denoted by `name`.

How can this help with our replica tests? If we look back to the supervision tree we defined earlier in this guide, you will find this:

```elixir
children = [
  MyApp.Repo,
  MyApp.Repo.Replica1,
  MyApp.Repo.Replica2,
  MyApp.Repo.Replica3,
  MyApp.Repo.Replica4
]
```

We are starting five different repositories and five different connection pools. Since we want the replica repositories to use the `MyApp.Repo`, we can achieve this by doing the following on the setup of each test:

```elixir
@replicas [
  MyApp.Repo.Replica1,
  MyApp.Repo.Replica2,
  MyApp.Repo.Replica3,
  MyApp.Repo.Replica4
]

setup do
  for replica <- @replicas do
    replica.put_dynamic_repo(MyApp.Repo)
  end

  :ok
end
```

Note `put_dynamic_repo` is per process. So every time you spawn a new process, the `dynamic_repo` value will reset to its default until you call `put_dynamic_repo` again.

Luckily, there is even a better way! We can pass a `:default_dynamic_repo` option when we define the repository. In this case, we want to set the `:default_dynamic_repo` to `MyApp.Repo` only during the test environment. In your `lib/my_app/repo.ex`, do this:

```elixir
  for repo <- @replicas do
    default_dynamic_repo =
      if Mix.env() == :test do
        MyApp.Repo
      else
        repo
      end

    defmodule repo do
      use Ecto.Repo,
        otp_app: :my_app,
        adapter: Ecto.Adapters.Postgres,
        read_only: true,
        default_dynamic_repo: default_dynamic_repo
    end
  end
```

And now your tests should work as before, while still being able to detect if you accidentally perform a write operation in a replica.

## Dynamic repositories

At this point, we have learned that Ecto allows you to start multiple connections based on the same repository. This is typically useful when you have to connect multiple databases or perform short-lived database connections.

For example, you can start a repository with a given set of credentials dynamically, like this:

```elixir
MyApp.Repo.start_link(
  name: :some_client,
  hostname: "client.example.com",
  username: "...",
  password: "...",
  pool_size: 1
)
```

In other words, `start_link` accepts the same options as the database configuration. Now let's do a query on the dynamically started repository. If you attempt to simply perform `MyApp.Repo.all(Post)`, it may fail, as by default it will try to use a process named `MyApp.Repo`, which may or may not be running. So don't forget to call `put_dynamic_repo/1` before:

```elixir
MyApp.Repo.put_dynamic_repo(:some_client)
MyApp.Repo.all(Post)
```

Ecto also allows you to start a repository with no name (just like that famous horse). In such cases, you need to explicitly pass `name: nil` and match on the result of `MyApp.Repo.start_link/1` to retrieve the PID, which should be given to `put_dynamic_repo`. Let's also use this opportunity and perform proper database clean-up, by shutting up the new repository and reverting the value of `put_dynamic_repo`:

```elixir
default_dynamic_repo = MyApp.Repo.get_dynamic_repo()

{:ok, repo} =
  MyApp.Repo.start_link(
    name: nil,
    hostname: "client.example.com",
    username: "...",
    password: "...",
    pool_size: 1
  )

try do
  MyApp.Repo.put_dynamic_repo(repo)
  MyApp.Repo.all(Post)
after
  MyApp.Repo.put_dynamic_repo(default_dynamic_repo)
  Supervisor.stop(repo)
end
```

We can encapsulate all of this in a function too, which you could define in your repository:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo, ...

  def with_dynamic_repo(credentials, callback) do
    default_dynamic_repo = get_dynamic_repo()
    start_opts = [name: nil, pool_size: 1] ++ credentials
    {:ok, repo} = MyApp.Repo.start_link(start_opts)

    try do
      MyApp.Repo.put_dynamic_repo(repo)
      callback.()
    after
      MyApp.Repo.put_dynamic_repo(default_dynamic_repo)
      Supervisor.stop(repo)
    end
  end
end
```

And now use it as:

```elixir
credentials = [
  hostname: "client.example.com",
  username: "...",
  password: "..."
]

MyApp.Repo.with_dynamic_repo(credentials, fn ->
  MyApp.Repo.all(Post)
end)
```

And that's it! Now you can have dynamic connections, all properly encapsulated in a single function and built on top of the dynamic repo API.
