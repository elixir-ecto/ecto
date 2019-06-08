defmodule Ecto.EmbedOneTest do
  use ExUnit.Case, async: true

  defmodule Supplier do
    use Ecto.Schema
    import Ecto.Changeset

    schema "suppliers" do
      embeds_one :info, Info, on_replace: :delete do
        field :account, :string
      end
    end

    def changeset(supplier, attrs) do
      supplier
      |> cast(attrs, [])
      |> cast_embed(:info, with: &info_changeset/2)
    end

    def info_changeset(schema, attrs) do
      schema
      |> cast(attrs, [:account])
    end
  end

  test "embeds_one" do
    params = %{
      id: 1,
      info: %{account: "Help"}
    }

    changeset =
      %Supplier{info: %Supplier.Info{account: "some"}}
      |> Supplier.changeset(params)

    assert Ecto.Embedded.prepare(changeset, [:info], nil, :update)
  end
end
