defmodule Ecto.Query.NormalizerTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Queryable
  alias Ecto.Query.Query
  alias Ecto.Query.Util

  defmodule Post do
    use Ecto.Model

    queryable :posts do
      field :title, :string
      field :text, :string
    end
  end

  test "auto select entity" do
    query = from(Post) |> Queryable.to_query |> Util.normalize
    assert { :&, _, [0] } = query.select.expr
  end

  test "group by all fields" do
    query = from(p in Post, group_by: p) |> Queryable.to_query |> Util.normalize
    var = { :&, [], [0] }
    assert [{ var, :id }, { var, :title }, { var, :text }] = Enum.first(query.group_bys).expr
  end
end
