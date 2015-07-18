alias Ecto.TestRepo

defmodule Ecto.Model.AutogenerateTest do
  use ExUnit.Case, async: true

  defmodule MyModel do
    use Ecto.Model

    schema "my_model" do
      field :z, Ecto.UUID, autogenerate: true
    end
  end

  ## Autogenerate

  @uuid "30313233-3435-3637-3839-616263646566"

  test "autogenerates values" do
    model = TestRepo.insert!(%MyModel{})
    assert byte_size(model.z) == 36

    changeset = Ecto.Changeset.cast(%MyModel{}, %{}, [], [])
    model = TestRepo.insert!(changeset)
    assert byte_size(model.z) == 36

    changeset = Ecto.Changeset.cast(%MyModel{}, %{z: nil}, [], [])
    model = TestRepo.insert!(changeset)
    assert byte_size(model.z) == 36

    changeset = Ecto.Changeset.cast(%MyModel{}, %{z: @uuid}, [:z], [])
    model = TestRepo.insert!(changeset)
    assert model.z == @uuid
  end
end
