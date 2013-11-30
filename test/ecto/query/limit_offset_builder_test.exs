defmodule Ecto.Query.LimitOffsetBuilderTest do
  use ExUnit.Case, async: true

  import Support.CompileHelpers
  import Ecto.Query, warn: false

  defmodule Post do
    use Ecto.Model

    queryable :posts do
      field :title, :string
    end
  end

  test "limit and offset" do
    delay_compile do
      x = 1
      from(Post) |> limit([], x * 3) |> offset([], 4 * 2) |> select([], 0)
    end

    assert_raise Ecto.InvalidQueryError, %r"limit and offset expressions must be a single integer value", fn ->
      delay_compile from(Post) |> limit([], "a") |> select([], 0)
    end
  end
end
