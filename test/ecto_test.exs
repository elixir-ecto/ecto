defmodule EctoTest do
  use ExUnit.Case, async: true

  alias Ecto.Query.Planner

  defmodule PrefixSchema do
    use Ecto.Schema

    @schema_prefix "owner_prefix"
    schema "prefix_schema" do
      has_one :no_prefix_assoc, EctoTest.NoPrefixAssoc
      has_one :prefix_assoc, EctoTest.PrefixAssoc
    end
  end

  defmodule NoPrefixAssoc do
    use Ecto.Schema

    schema "no_prefix_assoc" do
      belongs_to :prefix_schema, EctoTest.PrefixSchema
      has_one :no_prefix_nested_assoc, EctoTest.NoPrefixNestedAssoc
    end
  end

  defmodule PrefixAssoc do
    use Ecto.Schema

    @schema_prefix "assoc_prefix"
    schema "prefix_assoc" do
      belongs_to :prefix_schema, EctoTest.PrefixSchema
    end
  end

  defmodule NoPrefixNestedAssoc do
    use Ecto.Schema

    schema "no_prefix_nested_assoc" do
      belongs_to :no_prefix_nested_assoc, EctoTest.NoPrefixAssoc
    end
  end

  test "Ecto.assoc/3: struct prefix is assigned to assoc with no prefix" do
    # One struct
    query =
      %PrefixSchema{id: 1}
      |> Ecto.assoc(:no_prefix_assoc)
      |> normalize()

    assert query.sources == {{"no_prefix_assoc", EctoTest.NoPrefixAssoc, "owner_prefix"}}

    # Multiple structs
    query =
      [%PrefixSchema{id: 1}, %PrefixSchema{id: 2}]
      |> Ecto.assoc(:no_prefix_assoc)
      |> normalize()

    assert query.sources == {{"no_prefix_assoc", EctoTest.NoPrefixAssoc, "owner_prefix"}}
  end

  test "Ecto.assoc/3: struct prefix is not assigned to assoc that already has a prefix" do
    # One struct
    query =
      %PrefixSchema{id: 1}
      |> Ecto.assoc(:prefix_assoc)
      |> normalize()

    assert query.sources == {{"prefix_assoc", EctoTest.PrefixAssoc, "assoc_prefix"}}

    # Multiple structs
    query =
      [%PrefixSchema{id: 1}, %PrefixSchema{id: 2}]
      |> Ecto.assoc(:prefix_assoc)
      |> normalize()

    assert query.sources == {{"prefix_assoc", EctoTest.PrefixAssoc, "assoc_prefix"}}
  end

  test "Ecto.assoc/3: struct prefix is assigned to chain of assocs with no prefixes" do
    query =
      %PrefixSchema{id: 1}
      |> Ecto.assoc([:no_prefix_assoc, :no_prefix_nested_assoc])
      |> normalize()

    assert query.sources ==
             {{"no_prefix_nested_assoc", EctoTest.NoPrefixNestedAssoc, "owner_prefix"},
              {"no_prefix_assoc", EctoTest.NoPrefixAssoc, "owner_prefix"}}
  end

  test "Ecto.assoc/3: prefix option is assigned to assoc instead of struct's prefix" do
    query =
      %PrefixSchema{id: 1}
      |> Ecto.assoc(:no_prefix_assoc, prefix: "prefix_opt")
      |> normalize()

    assert query.sources == {{"no_prefix_assoc", EctoTest.NoPrefixAssoc, "prefix_opt"}}
  end

  defp plan(query, operation) do
    Planner.plan(query, operation, Ecto.TestAdapter)
  end

  defp normalize(query, operation \\ :all) do
    {query, _params, _key} = plan(query, operation)

    {query, _select} =
      query
      |> Planner.ensure_select(operation == :all)
      |> Planner.normalize(operation, Ecto.TestAdapter, 0)

    query
  end

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field :title, :string, default: "default title"
      field :body, :string
      belongs_to :author, Author
    end
  end

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field :name, :string
      has_many :posts, Post
    end
  end

  test "Ecto.reset_fields/2 resets fields" do
    post = %Post{
      title: "hello world",
      body: "This is a beautiful world.",
      author: %Author{},
    }

    assert %Post{
             title: "default title",
             body: "This is a beautiful world.",
             author: build_not_loaded(Post, :author),
           } == Ecto.reset_fields(post, [:title, :author])
  end

  defp build_not_loaded(schema, association) do
    %{
      cardinality: cardinality,
      field: field,
      owner: owner
    } = schema.__schema__(:association, association)

    %Ecto.Association.NotLoaded{
      __cardinality__: cardinality,
      __field__: field,
      __owner__: owner
    }
  end
end
