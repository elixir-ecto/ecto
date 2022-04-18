# Testing with Ecto

After you have successfully set up your database connection with Ecto for your application,
its usage for your tests requires further changes, especially if you want to leverage the
[Ecto SQL Sandbox](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html) that allows
you to run tests that talk to the database concurrently.

Create the `config/test.exs` file or append the following content:

```elixir
use Mix.Config

config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  database: "myapp_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

 ```

Thereby, we configure the database connection for our test setup.
In this case, we use a Postgres database and set it up to use the sandbox pool that will wrap each test in a transaction.

Make sure we import the configuration for the test environment at the very bottom of `config/config.exs`:

```elixir
import_config "#{Mix.env()}.exs"
```

We also need to add an explicit statement to the end of `test/test_helper.exs` about the `sandbox` mode:

```elixir
Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, :manual)
```

Lastly, you need to establish the database connection ahead of your tests.
You can enable it either for all of your test cases by extending the `ExUnit` template or by setting it up individually for each test. Let's start with the former and place it to the `test/support/repo_case.ex`:

```elixir
defmodule MyApp.RepoCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias MyApp.Repo

      import Ecto
      import Ecto.Query
      import MyApp.RepoCase

      # and any other stuff
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, {:shared, self()})
    end

    :ok
  end
end
```

The case template above brings `Ecto` and `Ecto.Query` functions into your tests and checks-out a database connection. It also enables a shared sandbox connection mode in case the test is not running asynchronously.
See [`Ecto.Adapters.SQL.Sandbox`](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html) for more information.

To add `test/support/` folder for compilation in test environment we need to update `mix.exs` configuration

```elixir
  def project do
    [
      # ...
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
```

And then in each test that uses the repository:

```elixir
defmodule MyApp.MyTest do
  use MyApp.RepoCase

  # Tests etc...
end
```

In case you don't want to define a "case template", you can checkout on each individual case:

```elixir
defmodule MyApp.MyTest do
  use ExUnit.Case

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo)
  end

  # Tests etc...
end
```

For convenience reasons, you can also define `aliases` to automatically set up your database at the execution of your tests.
Change the following content in your `mix.exs`.

```elixir

  def project do
    [app: :my_app,

     ...

     aliases: aliases()]
  end

  defp aliases do
    [ ...
     "test": ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end
```
