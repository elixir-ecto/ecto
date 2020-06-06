# Test factories

Many projects depend on external libraries to build their test data. Some of those libraries are called factories because they provide convenience functions for producing different groups of data. However, given Ecto is able to manage complex data trees, we can implement such functionality without relying on third-party projects.

To get started, let's create a file at "test/support/factory.ex" with the following contents:

```elixir
defmodule MyApp.Factory do
  alias MyApp.Repo

  # Factories

  def build(:post) do
    %MyApp.Post{title: "hello world"}
  end

  def build(:comment) do
    %MyApp.Comment{body: "good post"}
  end

  def build(:post_with_comments) do
    %MyApp.Post{
      title: "hello with comments",
      comments: [
        build(:comment, body: "first"),
        build(:comment, body: "second")
      ]
    }
  end

  def build(:user) do
    %MyApp.User{
      email: "hello#{System.unique_integer()}",
      username: "hello#{System.unique_integer()}"
    }
  end

  # Convenience API

  def build(factory_name, attributes) do
    factory_name |> build() |> struct!(attributes)
  end

  def insert!(factory_name, attributes \\ []) do
    factory_name |> build(attributes) |> Repo.insert!()
  end
end
```

Our factory module defines four "factories" as different clauses to the build function: `:post`, `:comment`, `:post_with_comments` and `:user`. Each clause defines structs with the fields that are required by the database. In certain cases, the generated struct also needs to generate unique fields, such as the user's email and username. We did so by calling Elixir's `System.unique_integer()` - you could call `System.unique_integer([:positive])` if you need a strictly positive number.

At the end, we defined two functions, `build/2` and `insert!/2`, which are conveniences for building structs with specific attributes and for inserting data directly in the repository respectively.

That's literally all that is necessary for building our factories. We are now ready to use them in our tests. First, open up your "mix.exs" and make sure the "test/support/factory.ex" file is compiled:

```elixir
def project do
  [...,
   elixirc_paths: elixirc_paths(Mix.env),
   ...]
end

defp elixirc_paths(:test), do: ["lib", "test/support"]
defp elixirc_paths(_), do: ["lib"]
```

Now in any of the tests that need to generate data, we can import the `MyApp.Factory` module and use its functions:

```elixir
import MyApp.Factory

build(:post)
#=> %MyApp.Post{id: nil, title: "hello world", ...}

build(:post, title: "custom title")
#=> %MyApp.Post{id: nil, title: "custom title", ...}

insert!(:post, title: "custom title")
#=> %MyApp.Post{id: ..., title: "custom title"}
```

By building the functionality we need on top of Ecto capabilities, we are able to extend and improve our factories on whatever way we desire, without being constrained to third-party limitations.
