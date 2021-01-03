alias Ecto.TestRepo

defmodule Ecto.Repo.AutogenerateTest do
  use ExUnit.Case, async: true

  defmodule Manager do
    use Ecto.Schema

    @timestamps_opts [inserted_at: :created_on]
    schema "manager" do
      field :company_id, :integer
      timestamps updated_at: :updated_on, type: :utc_datetime
    end
  end

  defmodule Office do
    use Ecto.Schema

    schema "offices" do
      field :name, :string
      belongs_to :company, Company
      timestamps type: :utc_datetime_usec
    end

    def changeset(module, changes) do
      module
      |> Ecto.Changeset.cast(changes, [:id, :name])
    end
  end

  defmodule Company do
    use Ecto.Schema

    schema "default" do
      field :code, Ecto.UUID, autogenerate: true
      has_one :manager, Manager
      has_many :offices, Office
      timestamps()
    end
  end

  defmodule NaiveMod do
    use Ecto.Schema

    schema "naive_mod" do
      timestamps(type: :naive_datetime)
    end
  end

  defmodule NaiveUsecMod do
    use Ecto.Schema

    schema "naive_usec_mod" do
      timestamps(type: :naive_datetime_usec)
    end
  end

  defmodule UtcMod do
    use Ecto.Schema

    schema "utc_mod" do
      timestamps(type: :utc_datetime)
    end
  end

  defmodule UtcUsecMod do
    use Ecto.Schema

    schema "utc_usec_mod" do
      timestamps(type: :utc_datetime_usec)
    end
  end

  defmodule ParameterizedTypePrefixedUUID do
    use Ecto.ParameterizedType

    @separator "_"

    def init(opts), do: Enum.into(opts, %{})
    def type(_), do: :uuid

    def cast(data, %{prefix: prefix}) do
      if String.starts_with?(data, [prefix <> @separator]) do
        {:ok, data}
      else
        {:ok, prefix <> @separator <> data}
      end
    end

    def load(uuid, _, %{prefix: prefix}), do: {:ok, prefix <> @separator <> uuid}

    def dump(nil, _, _), do: {:ok, nil}

    def dump(data, _, %{prefix: _prefix}),
      do: {:ok, data |> String.split(@separator) |> List.last()}

    def autogenerate(%{autogenerate: true, prefix: prefix, field: :code, schema: _}),
      do: prefix <> @separator <> Ecto.UUID.generate()
  end

  defmodule ParameterizedTypePrefixedID do
    use Ecto.ParameterizedType

    @separator "_"

    def init(opts), do: Enum.into(opts, %{})
    def type(_), do: :id

    def cast(data, %{prefix: prefix}) do
      if String.starts_with?(data, [prefix <> @separator]) do
        {:ok, data}
      else
        {:ok, prefix <> @separator <> data}
      end
    end

    def load(id, _, %{prefix: prefix}), do: {:ok, prefix <> @separator <> to_string(id)}

    def dump(nil, _, _), do: {:ok, nil}
    def dump(data, _, %{prefix: _prefix}),
      do: {:ok, data |> String.split(@separator) |> List.last() |> Integer.parse()}
  end

  defmodule ParameterizedTypeSchema do
    use Ecto.Schema

    @primary_key {:id, ParameterizedTypePrefixedID, autogenerate: true, prefix: "pk"}
    schema "parameterized_type_schema" do
      field :code, ParameterizedTypePrefixedUUID, autogenerate: true, prefix: "code"
    end
  end

  ## Autogenerate

  @uuid "30313233-3435-4637-9839-616263646566"

  test "autogenerates values" do
    schema = TestRepo.insert!(%Company{})
    assert byte_size(schema.code) == 36

    changeset = Ecto.Changeset.cast(%Company{}, %{}, [])
    schema = TestRepo.insert!(changeset)
    assert byte_size(schema.code) == 36

    changeset = Ecto.Changeset.cast(%Company{}, %{code: nil}, [])
    schema = TestRepo.insert!(changeset)
    assert byte_size(schema.code) == 36

    changeset = Ecto.Changeset.force_change(changeset, :code, nil)
    schema = TestRepo.insert!(changeset)
    assert schema.code == nil

    changeset = Ecto.Changeset.cast(%Company{}, %{code: @uuid}, [:code])
    schema = TestRepo.insert!(changeset)
    assert schema.code == @uuid

    schema = TestRepo.insert!(%ParameterizedTypeSchema{})
    assert "pk_" <> _id = schema.id
    assert "code_" <> code_uuid = schema.code
    assert byte_size(code_uuid) == 36
  end

  ## Timestamps

  test "sets inserted_at and updated_at values" do
    default = TestRepo.insert!(%Company{})
    assert %NaiveDateTime{microsecond: {0, 0}} = default.inserted_at
    assert %NaiveDateTime{microsecond: {0, 0}} = default.updated_at
    assert default.inserted_at == default.updated_at
    assert_received {:insert, _}

    # No change
    changeset = Ecto.Changeset.change(%Company{id: 1})
    default = TestRepo.update!(changeset)
    refute default.inserted_at
    refute default.updated_at
    refute_received {:update, _}

    # Change in children
    changeset = Ecto.Changeset.change(%Company{id: 1})
    default = TestRepo.update!(Ecto.Changeset.put_assoc(changeset, :manager, %Manager{}))
    refute default.inserted_at
    refute default.updated_at
    assert_received {:insert, _}
    refute_received {:update, _}

    # Force change
    changeset = Ecto.Changeset.change(%Company{id: 1})
    default = TestRepo.update!(changeset, force: true)
    refute default.inserted_at
    assert %NaiveDateTime{microsecond: {0, 0}} = default.updated_at
    assert_received {:update, _}
  end

  test "does not update updated_at when the associated record did not change" do
    company = TestRepo.insert!(%Company{offices: [%Office{id: 1, name: "1"}, %Office{id: 2, name: "2"}]})
    [office_one, office_two] = company.offices

    changes = %{offices: [%{id: 1, name: "updated"}, %{id: 2, name: "2"}]}
    updated_company =
      company
      |> Ecto.Changeset.cast(changes, [])
      |> Ecto.Changeset.cast_assoc(:offices)
      |> TestRepo.update!()
    [updated_office_one, updated_office_two] = updated_company.offices
    assert updated_office_one.updated_at != office_one.updated_at
    assert updated_office_two.updated_at == office_two.updated_at
  end

  test "does not set inserted_at and updated_at values if they were previously set" do
    naive_datetime = ~N[2000-01-01 00:00:00]
    default = TestRepo.insert!(%Company{inserted_at: naive_datetime,
                                        updated_at: naive_datetime})
    assert default.inserted_at == naive_datetime
    assert default.updated_at == naive_datetime

    changeset = Ecto.Changeset.change(%Company{id: 1}, updated_at: naive_datetime)
    default = TestRepo.update!(changeset)
    refute default.inserted_at
    assert default.updated_at == naive_datetime
  end

  test "sets custom inserted_at and updated_at values" do
    default = TestRepo.insert!(%Manager{})
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {0, 0}} = default.created_on
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {0, 0}} = default.updated_on
    assert default.created_on == default.updated_on

    default = TestRepo.update!(%Manager{id: 1} |> Ecto.Changeset.change, force: true)
    refute default.created_on
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {0, 0}} = default.updated_on
  end

  test "sets the timestamps type to naive_datetime" do
    default = TestRepo.insert!(%NaiveMod{})
    assert %NaiveDateTime{microsecond: {0, 0}} = default.inserted_at
    assert %NaiveDateTime{microsecond: {0, 0}} = default.updated_at
    assert default.inserted_at == default.updated_at

    default = TestRepo.update!(%NaiveMod{id: 1} |> Ecto.Changeset.change, force: true)
    refute default.inserted_at
    assert %NaiveDateTime{microsecond: {0, 0}} = default.updated_at
  end

  test "sets the timestamps type to naive_datetime_usec" do
    default = TestRepo.insert!(%NaiveUsecMod{})
    assert %NaiveDateTime{microsecond: {_, 6}} = default.inserted_at
    assert %NaiveDateTime{microsecond: {_, 6}} = default.updated_at
    assert default.inserted_at == default.updated_at

    default = TestRepo.update!(%NaiveUsecMod{id: 1} |> Ecto.Changeset.change, force: true)
    refute default.inserted_at
    assert %NaiveDateTime{microsecond: {_, 6}} = default.updated_at
  end

  test "sets the timestamps type to utc_datetime" do
    default = TestRepo.insert!(%UtcMod{})
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {0, 0}} = default.inserted_at
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {0, 0}} = default.updated_at
    assert default.inserted_at == default.updated_at

    default = TestRepo.update!(%UtcMod{id: 1} |> Ecto.Changeset.change, force: true)
    refute default.inserted_at
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {0, 0}} = default.updated_at
  end

  test "sets the timestamps type to utc_datetime_usec" do
    default = TestRepo.insert!(%UtcUsecMod{})
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {_, 6}} = default.inserted_at
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {_, 6}} = default.updated_at
    assert default.inserted_at == default.updated_at

    default = TestRepo.update!(%UtcUsecMod{id: 1} |> Ecto.Changeset.change, force: true)
    refute default.inserted_at
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {_, 6}} = default.updated_at
  end
end
