Code.require_file "../../test_helper.exs", __DIR__

defmodule Ecto.Query.NormalizerTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  defmodule PostEntity do
    use Ecto.Entity

    schema :post_entity do
      field :title, :string
    end
  end

  defmodule CommentEntity do
    use Ecto.Entity

    schema :post_entity do
      field :text, :string
    end
  end


  test "auto select entity" do
    query = from(p in PostEntity) |> normalize
    assert { { :entity, :entity }, { :entity, [], nil } } = query.select.expr
    assert [:entity] == query.select.binding
  end

  test "dont auto select entity" do
    query = from(p in PostEntity) |> from(c in CommentEntity) |> normalize
    refute query.select
  end
end
