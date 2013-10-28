defmodule Ecto.Model.QueryableTest do
  use ExUnit.Case, async: true

  test "imports Ecto.Query functions" do
    defmodule Import do
      use Ecto.Model.Queryable

      queryable "imports" do
        field :name, :string
      end

      def from_1 do
        from(c in __MODULE__)
      end

      def from_2 do
        from(c in __MODULE__, where: c.name == nil)
      end
    end

    assert Import.from_1 == Import
    assert is_record(Import.from_2, Ecto.Query.Query)
  end
end
