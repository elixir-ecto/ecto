defmodule Ecto.Query.NormalizerTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Queryable
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
    assert { { :entity, :entity }, { :entity, [], nil } } = query.select.expr
    assert [:entity] == query.select.binding
  end

  test "dont auto select entity" do
    query = from(PostEntity) |> from(CommentEntity) |> Util.normalize
    refute query.select
  end
end
