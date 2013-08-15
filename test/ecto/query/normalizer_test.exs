defmodule Ecto.Query.NormalizerTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Queryable
  alias Ecto.Query.Query
  alias Ecto.Query.Util

  defmodule PostEntity do
    use Ecto.Entity

    dataset :post_entity do
      field :title, :string
    end
  end

  defmodule CommentEntity do
    use Ecto.Entity

    dataset :post_entity do
      field :text, :string
    end
  end

  test "auto select entity" do
    query = from(PostEntity) |> Queryable.to_query |> Util.normalize
    assert { :&, _, [0] } = query.select.expr
  end
end
