alias Ecto.TestRepo

defmodule Ecto.Repo.AutogenerateTest do
  use ExUnit.Case, async: true

  defmodule Config do
    use Ecto.Schema

    @timestamps_opts [inserted_at: :created_on]
    schema "config" do
      timestamps updated_at: :updated_on
    end
  end

  defmodule Default do
    use Ecto.Schema

    schema "default" do
      field :z, Ecto.UUID, autogenerate: true
      has_one :config, Config
      timestamps()
    end
  end

  ## Autogenerate

  @uuid "30313233-3435-3637-3839-616263646566"

  test "autogenerates values" do
    schema = TestRepo.insert!(%Default{})
    assert byte_size(schema.z) == 36

    changeset = Ecto.Changeset.cast(%Default{}, %{}, [])
    schema = TestRepo.insert!(changeset)
    assert byte_size(schema.z) == 36

    changeset = Ecto.Changeset.cast(%Default{}, %{z: nil}, [])
    schema = TestRepo.insert!(changeset)
    assert byte_size(schema.z) == 36

    changeset = Ecto.Changeset.force_change(changeset, :z, nil)
    schema = TestRepo.insert!(changeset)
    assert schema.z == nil

    changeset = Ecto.Changeset.cast(%Default{}, %{z: @uuid}, [:z])
    schema = TestRepo.insert!(changeset)
    assert schema.z == @uuid
  end

  ## Timestamps

  test "sets inserted_at and updated_at values" do
    default = TestRepo.insert!(%Default{})
    assert %NaiveDateTime{} = default.inserted_at
    assert %NaiveDateTime{} = default.updated_at
    assert_received :insert

    # No change
    changeset = Ecto.Changeset.change(%Default{id: 1})
    default = TestRepo.update!(changeset)
    refute default.inserted_at
    refute default.updated_at
    refute_received :update

    # Change in children
    changeset = Ecto.Changeset.change(%Default{id: 1})
    default = TestRepo.update!(Ecto.Changeset.put_assoc(changeset, :config, %Config{}))
    refute default.inserted_at
    refute default.updated_at
    assert_received :insert
    refute_received :update

    # Force change
    changeset = Ecto.Changeset.change(%Default{id: 1})
    default = TestRepo.update!(changeset, force: true)
    refute default.inserted_at
    assert %NaiveDateTime{} = default.updated_at
    assert_received :update
  end

  test "does not set inserted_at and updated_at values if they were previously set" do
    {:ok, naive_datetime} = NaiveDateTime.new(2000, 1, 1, 0, 0, 0)
    default = TestRepo.insert!(%Default{inserted_at: naive_datetime,
                                        updated_at: naive_datetime})
    assert default.inserted_at == naive_datetime
    assert default.updated_at == naive_datetime

    changeset = Ecto.Changeset.change(%Default{id: 1}, updated_at: naive_datetime)
    default = TestRepo.update!(changeset)
    refute default.inserted_at
    assert default.updated_at == naive_datetime
  end

  test "sets custom inserted_at and updated_at values" do
    default = TestRepo.insert!(%Config{})
    assert %NaiveDateTime{} = default.created_on
    assert %NaiveDateTime{} = default.updated_on

    default = TestRepo.update!(%Config{id: 1} |> Ecto.Changeset.change, force: true)
    refute default.created_on
    assert %NaiveDateTime{} = default.updated_on
  end
end
