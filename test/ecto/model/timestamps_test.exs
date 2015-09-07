defmodule Ecto.Model.TimestampsTest do
  use ExUnit.Case, async: true

  alias Ecto.TestRepo

  defmodule Default do
    use Ecto.Model

    schema "default" do
      timestamps
    end
  end

  defmodule Config do
    use Ecto.Model

    @timestamps_opts [inserted_at: :created_on]
    schema "default" do
      timestamps updated_at: :updated_on
    end
  end

  test "sets inserted_at and updated_at values" do
    default = TestRepo.insert!(%Default{})
    assert %Ecto.DateTime{} = default.inserted_at
    assert %Ecto.DateTime{} = default.updated_at

    default = TestRepo.update!(%Default{id: 1})
    refute default.inserted_at
    assert %Ecto.DateTime{} = default.updated_at
  end

  test "does not set inserted_at and updated_at values if they were previously set" do
    default = TestRepo.insert!(%Default{inserted_at: %Ecto.DateTime{year: 2000},
                                        updated_at: %Ecto.DateTime{year: 2000}})
    assert default.inserted_at == %Ecto.DateTime{year: 2000}
    assert default.updated_at == %Ecto.DateTime{year: 2000}

    default = TestRepo.update!(%Default{id: 1, updated_at: %Ecto.DateTime{year: 2000}})
    refute default.inserted_at
    assert default.updated_at != %Ecto.DateTime{year: 2000}

    changeset = Ecto.Changeset.change(%Default{id: 1}, updated_at: %Ecto.DateTime{year: 2000})
    default = TestRepo.update!(changeset)
    refute default.inserted_at
    assert default.updated_at == %Ecto.DateTime{year: 2000}
  end

  test "sets custom inserted_at and updated_at values" do
    default = TestRepo.insert!(%Config{})
    assert %Ecto.DateTime{} = default.created_on
    assert %Ecto.DateTime{} = default.updated_on

    default = TestRepo.update!(%Config{id: 1})
    refute default.created_on
    assert %Ecto.DateTime{} = default.updated_on
  end
end
