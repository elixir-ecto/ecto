Code.require_file "../test_helper.exs", __DIR__

defmodule Ecto.QueryTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  defmodule PostEntity do
    use Ecto.Entity
    table_name :post_entity

    field :title, :string
  end

  test "vars are order dependent" do
    query = from(p in PostEntity) |> select([q], q.title)
    validate(query)
  end
end
