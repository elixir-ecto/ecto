Code.require_file "../../support/test_repo.exs", __DIR__
alias Ecto.TestRepo

defmodule Ecto.Model.TimestampsTest do
  use ExUnit.Case, async: true

  defmodule Default do
    use Ecto.Model

    schema "default" do
      timestamps
    end
  end

  defmodule Config do
    use Ecto.Model

    @timestamps_opts [type: :datetime]
    schema "default" do
      timestamps inserted_at: :created_on, updated_at: :updated_on
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

  test "does not set inserted_at and updated_at values if they were previoously set" do
    default = TestRepo.insert!(%Default{inserted_at: %Ecto.DateTime{year: 2000},
                                       updated_at: %Ecto.DateTime{year: 2000}})
    assert %Ecto.DateTime{year: 2000} = default.inserted_at
    assert %Ecto.DateTime{year: 2000} = default.updated_at

    default = TestRepo.update!(%Default{id: 1, updated_at: %Ecto.DateTime{year: 2000}})
    refute default.inserted_at
    assert %Ecto.DateTime{year: 2000} = default.updated_at
  end

  test "sets custom inserted_at and updated_at values" do
    default = TestRepo.insert!(%Config{})
    assert {_, _} = default.created_on
    assert {_, _} = default.updated_on

    default = TestRepo.update!(%Config{id: 1})
    refute default.created_on
    assert {_, _} = default.updated_on
  end
end
