defmodule Ecto.EmbedOneTest do
  use ExUnit.Case, async: true

  alias Ecto.TestRepo, as: TestRepo

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
      %Supplier{
        id: 1,
        info: %Supplier.Info{
          account: "1234",
          id: nil
        }
      }
      |> Ecto.put_meta(state: :loaded)
      |> Ecto.put_meta(source: "suppliers")
      |> Supplier.changeset(params)
      |> TestRepo.update()
  end
end
