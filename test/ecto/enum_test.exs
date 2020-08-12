defmodule Ecto.EnumTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Ecto.TestRepo

  defmodule EnumSchema do
    use Ecto.Schema

    schema "my_schema" do
      field :my_enum, Ecto.Enum, values: [:foo, :bar, :baz]
    end
  end

  describe "Ecto.Enum" do
    test "schema" do
      assert EnumSchema.__schema__(:type, :my_enum) ==
               {:parameterized, Ecto.Enum,
                %{
                  on_load: %{"bar" => :bar, "baz" => :baz, "foo" => :foo},
                  on_dump: %{bar: "bar", baz: "baz", foo: "foo"}
                }}
    end

    test "bad values" do
      message = ~r"Ecto.Enum types must have a values option specified as a list of atoms"

      assert_raise ArgumentError, message, fn ->
        defmodule SchemaInvalidEnumValues do
          use Ecto.Schema

          schema "invalidvalues" do
            field :name, Ecto.Enum
          end
        end
      end

      assert_raise ArgumentError, message, fn ->
        defmodule SchemaInvalidEnumValues do
          use Ecto.Schema

          schema "invalidvalues" do
            field :name, Ecto.Enum, values: ["foo", "bar"]
          end
        end
      end
    end
  end

  describe "change" do
    test "change" do
      assert %Changeset{valid?: true, changes: %{my_enum: :foo}, errors: []} = Changeset.change(%EnumSchema{my_enum: false}, %{my_enum: :foo})
      assert %Changeset{valid?: false, errors: [{:my_enum, {"unknown enum value", value: 1}}]} = Changeset.change(%EnumSchema{}, %{my_enum: 1})
    end
  end

  describe "cast" do
    test "casts strings" do
      assert %Changeset{valid?: true, changes: %{my_enum: :foo}} =
               Changeset.cast(%EnumSchema{}, %{my_enum: "foo"}, [:my_enum])
    end

    test "casts atoms" do
      assert %Changeset{valid?: true, changes: %{my_enum: :bar}} =
               Changeset.cast(%EnumSchema{}, %{my_enum: :bar}, [:my_enum])
    end

    test "rejects bad strings" do
      type = EnumSchema.__schema__(:type, :my_enum)

      assert %Changeset{
               valid?: false,
               changes: %{},
               errors: [my_enum: {"is invalid", [type: ^type, validation: :cast]}]
             } = Changeset.cast(%EnumSchema{}, %{my_enum: "bar2"}, [:my_enum])
    end

    test "rejects bad atoms" do
      type = EnumSchema.__schema__(:type, :my_enum)

      assert %Changeset{
               valid?: false,
               changes: %{},
               errors: [my_enum: {"is invalid", [type: ^type, validation: :cast]}]
             } = Changeset.cast(%EnumSchema{}, %{my_enum: :bar2}, [:my_enum])
    end
  end

  describe "dump" do
    test "accepts valid values" do
      assert %EnumSchema{my_enum: :foo} = TestRepo.insert!(%EnumSchema{my_enum: :foo})
      assert_receive {:insert, %{fields: [my_enum: "foo"]}}
    end

    test "rejects invalid atom" do
      msg =
        "value `:foo2` for `Ecto.EnumTest.EnumSchema.my_enum` in `insert` does not match type #{
          inspect(EnumSchema.__schema__(:type, :my_enum))
        }"

      assert_raise Ecto.ChangeError, msg, fn ->
        TestRepo.insert!(%EnumSchema{my_enum: :foo2})
      end

      refute_received _
    end

    test "rejects invalid value" do
      msg =
        "value `[:a, :b, :c]` for `Ecto.EnumTest.EnumSchema.my_enum` in `insert` does not match type #{
          inspect(EnumSchema.__schema__(:type, :my_enum))
        }"

      assert_raise Ecto.ChangeError, msg, fn ->
        TestRepo.insert!(%EnumSchema{my_enum: [:a, :b, :c]})
      end

      refute_received _
    end
  end

  describe "load" do
    test "loads valid values" do
      Process.put(:test_repo_all_results, {1, [[1, "foo", nil]]})
      assert [%Ecto.EnumTest.EnumSchema{my_enum: :foo}] = TestRepo.all(EnumSchema)
    end

    test "reject invalid values" do
      Process.put(:test_repo_all_results, {1, [[1, "foo2", nil]]})

      assert_raise ArgumentError, ~r/cannot load `\"foo2\"` as type/, fn ->
        TestRepo.all(EnumSchema)
      end
    end
  end
end
