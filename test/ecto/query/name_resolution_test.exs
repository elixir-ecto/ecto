defmodule Ecto.Query.NameResolutionTest do
  use ExUnit.Case, async: true

  alias Ecto.Query
  alias Ecto.Query.NameResolution

  defmodule Foo do
    use Ecto.Model
    queryable "foo" do
    end
  end

  defmodule Bar do
    use Ecto.Model
    queryable "bar" do
    end
  end

  test "use first letter and number for name" do
    query = Query.Query[sources: {{"model", Foo.Entity, Foo.Model}}]
    assert NameResolution.create_names(query) == {{{"model", "m0"}, Ecto.Query.NameResolutionTest.Foo.Entity, Ecto.Query.NameResolutionTest.Foo.Model}}
  end

  test "allows for multiple models" do
    query = Query.Query[sources: {{"model", Foo.Entity, Foo.Model}, {"model", Bar.Entity, Bar.Model}}]
    assert NameResolution.create_names(query) == {{{"model", "m0"}, Ecto.Query.NameResolutionTest.Foo.Entity, Ecto.Query.NameResolutionTest.Foo.Model}, {{"model", "m1"}, Ecto.Query.NameResolutionTest.Bar.Entity, Ecto.Query.NameResolutionTest.Bar.Model}}
  end
end
