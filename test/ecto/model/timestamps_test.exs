Code.require_file "../../support/mock_repo.exs", __DIR__
alias Ecto.MockRepo

defmodule Ecto.Model.TimestampsTest do
  use ExUnit.Case, async: true

  defmodule Default do
    use Ecto.Model

    @timestamps_opts [usec: true]
    schema "default" do
      field :data, :boolean

      timestamps
    end
  end

  defmodule DefaultAlwaysUpdate do
    use Ecto.Model

    @timestamps_opts [usec: true, always_update: true]
    schema "default" do
      field :data, :boolean

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
    default = MockRepo.insert!(%Default{})
    assert %Ecto.DateTime{} = default.inserted_at
    assert %Ecto.DateTime{} = default.updated_at

    default = MockRepo.update!(%Default{id: 1})
    refute default.inserted_at
    assert %Ecto.DateTime{} = default.updated_at

    old_updated_at = default.updated_at

    # Since we're using usec timestamps, this should advance the timestamp by
    # 50 ms if it gets set
    :timer.sleep(50)

    default = MockRepo.update!(Ecto.Changeset.change(default, %{data: nil}))
    refute default.inserted_at
    assert default.updated_at == old_updated_at
  end

  test "sets inserted_at and updated_at values when always_update is enabled" do
    default = MockRepo.insert!(%DefaultAlwaysInsert{})
    assert %Ecto.DateTime{} = default.inserted_at
    assert %Ecto.DateTime{} = default.updated_at

    old_updated_at = default.updated_at

    # Since we're using usec timestamps, this should advance the timestamp by
    # 50 ms if it gets set
    :timer.sleep(50)

    default = MockRepo.update!(Ecto.Changeset.change(%DefaultAlwaysInsert{id: 1}, %{data: nil}))
    refute default.inserted_at
    assert default.updated_at != old_updated_at
  end

  test "does not set inserted_at and updated_at values if they were previoously set" do
    default = MockRepo.insert!(%Default{inserted_at: %Ecto.DateTime{year: 2000},
                                       updated_at: %Ecto.DateTime{year: 2000}})
    assert %Ecto.DateTime{year: 2000} = default.inserted_at
    assert %Ecto.DateTime{year: 2000} = default.updated_at

    default = MockRepo.update!(%Default{id: 1, updated_at: %Ecto.DateTime{year: 2000}})
    refute default.inserted_at
    assert %Ecto.DateTime{year: 2000} = default.updated_at
  end

  test "sets custom inserted_at and updated_at values" do
    default = MockRepo.insert!(%Config{})
    assert {_, _} = default.created_on
    assert {_, _} = default.updated_on

    default = MockRepo.update!(%Config{id: 1})
    refute default.created_on
    assert {_, _} = default.updated_on
  end
end
