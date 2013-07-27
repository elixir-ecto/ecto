defmodule Ecto.Query.LimitOffsetBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query, warn: false
  import Ecto.TestHelpers

  defmodule PostEntity do
    use Ecto.Entity

    dataset :post_entity do
      field :title, :string
    end
  end

  test "limit and offset" do
    delay_compile do
      x = 1
      from(p in PostEntity) |> limit([], x * 3) |> offset([], 4 * 2) |> select([], 0)
    end

    assert_raise Ecto.InvalidQuery, %r"limit and offset expressions must be a single integer value", fn ->
      delay_compile from(p in PostEntity) |> limit([], "a") |> select([], 0)
    end
  end
end
