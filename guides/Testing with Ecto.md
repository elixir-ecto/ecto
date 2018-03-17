# Testing with Ecto

After you have successfully set up your database connection with Ecto for your application,
its usage for your tests requires further changes. Create the `config/test.exs` file or append the following content:

```
use Mix.Config

config :my_app, MyApp.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "myapp_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox
 
 ```
 
Thereby, we configure the database connection for our test setup.
In this case, we use a `Postgres` database and set it up through the `sandbox` as temporary data storage for a test run only.

We also need to add an explicit statement to `test/test_helper.exs` about the `sandbox` mode:
```
Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, :manual)
```

If you do not start `Ecto` as an `extra_applications` in your `mix.exs`, you also need to explicitely start the `Repo` for your tests:
```
{:ok, _pid} = Drones.Repo.start_link
Ecto.Adapters.SQL.Sandbox.mode(Drones.Repo, :manual)
```

Lastly, you need to establish the database connection ahead of your tests.
You can enable it either for all of your test cases by extending the `ExUnit` template or by setting it up individually for each test.


```
defmodule MyApp.ModelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias MyApp.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import MyApp.ModelCase
      
      # and any other stuff
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo)
  end
end
```

```
defmodule MyTest do
  use MyApp.ModelCase
  
  # Tests etc...
end
```

The second alternative is presented in the following:

```
defmodule MyTest do
  use ExUnit.Case

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo)
  end
  
  # Tests etc...
end
```
