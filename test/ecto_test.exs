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
    {query, _, _} =
      %PrefixSchema{id: 1}
      |> Ecto.assoc(:no_prefix_assoc)
      |> normalize_with_params()

    # Multiple structs
    [%PrefixSchema{id: 1}, %PrefixSchema{id: 2}]
    |> Ecto.assoc(:no_prefix_assoc)
    |> normalize_with_params()

    assert query.sources == {{"no_prefix_assoc", EctoTest.NoPrefixAssoc, "owner_prefix"}}
  end

  test "Ecto.assoc/3: struct prefix is not assigned to assoc that already has a prefix" do
    # One struct
    {query, _, _} =
      %PrefixSchema{id: 1}
      |> Ecto.assoc(:prefix_assoc)
      |> normalize_with_params()

    assert query.sources == {{"prefix_assoc", EctoTest.PrefixAssoc, "assoc_prefix"}}

    # Multiple structs
    {query, _, _} =
      [%PrefixSchema{id: 1}, %PrefixSchema{id: 2}]
      |> Ecto.assoc(:prefix_assoc)
      |> normalize_with_params()

    assert query.sources == {{"prefix_assoc", EctoTest.PrefixAssoc, "assoc_prefix"}}
  end

  test "Ecto.assoc/3: struct prefix is assigned to chain of assocs with no prefixes" do
    {query, _, _} =
      %PrefixSchema{id: 1}
      |> Ecto.assoc([:no_prefix_assoc, :no_prefix_nested_assoc])
      |> normalize_with_params()

    assert query.sources ==
             {{"no_prefix_nested_assoc", EctoTest.NoPrefixNestedAssoc, "owner_prefix"},
              {"no_prefix_assoc", EctoTest.NoPrefixAssoc, "owner_prefix"}}
  end

  test "Ecto.assoc/3: prefix option is assigned to assoc instead of struct's prefix" do
    {query, _, _} =
      %PrefixSchema{id: 1}
      |> Ecto.assoc(:no_prefix_assoc, prefix: "prefix_opt")
      |> normalize_with_params()

    assert query.sources == {{"no_prefix_assoc", EctoTest.NoPrefixAssoc, "prefix_opt"}}
  end

  defp plan(query, operation) do
    Planner.plan(query, operation, Ecto.TestAdapter)
  end

  defp normalize_with_params(query, operation \\ :all) do
    {query, params, _key} = plan(query, operation)

    {query, select} =
      query
      |> Planner.ensure_select(operation == :all)
      |> Planner.normalize(operation, Ecto.TestAdapter, 0)

    {query, params, select}
  end
end
