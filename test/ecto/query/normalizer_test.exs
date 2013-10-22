defmodule Ecto.Query.NormalizerTest do
  use Ecto.TestCase, async: true

  import Ecto.Query
  alias Ecto.Queryable
  alias Ecto.Query.Query
  alias Ecto.Query.Util

  defmodule Post do
    use Ecto.Model

    queryable :posts do
      field :title, :string
    end
  end

  test "auto select entity" do
    query = from(Post) |> Queryable.to_query |> Util.normalize
    assert { :&, _, [0] } = query.select.expr
  end
end
