defmodule Ecto.EnumTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Ecto.TestRepo

  defmodule EnumSchema do
    use Ecto.Schema

    schema "my_schema" do
      field :my_enum, Ecto.Enum, values: [:foo, :bar, :baz]
      field :my_enums, {:array, Ecto.Enum}, values: [:foo, :bar, :baz]
      field :virtual_enum, Ecto.Enum, values: [:foo, :bar, :baz], virtual: true
    end
  end

  describe "Ecto.Enum" do
    test "schema" do
      assert EnumSchema.__schema__(:type, :my_enum) ==
               {:parameterized, Ecto.Enum,
                %{
                  on_load: %{"bar" => :bar, "baz" => :baz, "foo" => :foo},
                  on_dump: %{bar: "bar", baz: "baz", foo: "foo"},
                  values: [:foo, :bar, :baz]
                }}

      assert EnumSchema.__schema__(:type, :my_enums) ==
               {
                 :array,
                 {:parameterized, Ecto.Enum,
                  %{
                    on_dump: %{bar: "bar", baz: "baz", foo: "foo"},
                    on_load: %{"bar" => :bar, "baz" => :baz, "foo" => :foo},
                    values: [:foo, :bar, :baz]
                  }}
               }
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

  describe "cast" do
    test "casts strings" do
      assert %Changeset{valid?: true, changes: %{my_enum: :foo}} =
               Changeset.cast(%EnumSchema{}, %{my_enum: "foo"}, [:my_enum])

      assert %Changeset{valid?: true, changes: %{my_enums: [:foo]}} =
               Changeset.cast(%EnumSchema{}, %{my_enums: ["foo"]}, [:my_enums])
    end

    test "casts atoms" do
      assert %Changeset{valid?: true, changes: %{my_enum: :bar}} =
               Changeset.cast(%EnumSchema{}, %{my_enum: :bar}, [:my_enum])

      assert %Changeset{valid?: true, changes: %{my_enums: [:bar]}} =
               Changeset.cast(%EnumSchema{}, %{my_enums: [:bar]}, [:my_enums])
    end

    test "rejects bad strings" do
      type = EnumSchema.__schema__(:type, :my_enum)

      assert %Changeset{
               valid?: false,
               changes: %{},
               errors: [my_enum: {"is invalid", [type: ^type, validation: :cast]}]
             } = Changeset.cast(%EnumSchema{}, %{my_enum: "bar2"}, [:my_enum])

      type = EnumSchema.__schema__(:type, :my_enums)

      assert %Changeset{
               valid?: false,
               changes: %{},
               errors: [my_enums: {"is invalid", [type: ^type, validation: :cast]}]
             } = Changeset.cast(%EnumSchema{}, %{my_enums: ["bar2"]}, [:my_enums])
    end

    test "rejects bad atoms" do
      type = EnumSchema.__schema__(:type, :my_enum)

      assert %Changeset{
               valid?: false,
               changes: %{},
               errors: [my_enum: {"is invalid", [type: ^type, validation: :cast]}]
             } = Changeset.cast(%EnumSchema{}, %{my_enum: :bar2}, [:my_enum])

      type = EnumSchema.__schema__(:type, :my_enums)

      assert %Changeset{
               valid?: false,
               changes: %{},
               errors: [my_enums: {"is invalid", [type: ^type, validation: :cast]}]
             } = Changeset.cast(%EnumSchema{}, %{my_enums: :bar2}, [:my_enums])
    end
  end

  describe "dump" do
    test "accepts valid values" do
      assert %EnumSchema{my_enum: :foo} = TestRepo.insert!(%EnumSchema{my_enum: :foo})
      assert_receive {:insert, %{fields: [my_enum: "foo"]}}

      assert %EnumSchema{my_enums: [:foo]} = TestRepo.insert!(%EnumSchema{my_enums: [:foo]})
      assert_receive {:insert, %{fields: [my_enums: ["foo"]]}}
    end

    test "rejects invalid atom" do
      msg =
        ~r"value `:foo2` for `Ecto.EnumTest.EnumSchema.my_enum` in `insert` does not match type"

      assert_raise Ecto.ChangeError, msg, fn ->
        TestRepo.insert!(%EnumSchema{my_enum: :foo2})
      end

      refute_received _
    end

    test "rejects invalid value" do
      msg =
        ~r"value `\[:a, :b, :c\]` for `Ecto.EnumTest.EnumSchema.my_enum` in `insert` does not match type"

      assert_raise Ecto.ChangeError, msg, fn ->
        TestRepo.insert!(%EnumSchema{my_enum: [:a, :b, :c]})
      end

      refute_received _
    end
  end

  describe "load" do
    test "loads valid values" do
      Process.put(:test_repo_all_results, {1, [[1, "foo", nil, nil]]})
      assert [%Ecto.EnumTest.EnumSchema{my_enum: :foo}] = TestRepo.all(EnumSchema)

      Process.put(:test_repo_all_results, {1, [[1, nil, ["foo"], nil]]})
      assert [%Ecto.EnumTest.EnumSchema{my_enums: [:foo]}] = TestRepo.all(EnumSchema)
    end

    test "reject invalid values" do
      Process.put(:test_repo_all_results, {1, [[1, "foo2", nil]]})

      assert_raise ArgumentError, ~r/cannot load `\"foo2\"` as type/, fn ->
        TestRepo.all(EnumSchema)
      end
    end
  end

  describe "values/2" do
    test "returns correct values" do
      assert Ecto.Enum.values(EnumSchema, :my_enum) == [:foo, :bar, :baz]
      assert Ecto.Enum.values(EnumSchema, :my_enums) == [:foo, :bar, :baz]
      assert Ecto.Enum.values(EnumSchema, :virtual_enum) == [:foo, :bar, :baz]
    end

    test "raises on bad schema" do
      assert_raise ArgumentError, "NotASchema is not an Ecto schema", fn ->
        Ecto.Enum.values(NotASchema, :foo)
      end
    end

    test "raises on bad field" do
      assert_raise ArgumentError, "foo is not an Ecto.Enum field", fn ->
        Ecto.Enum.values(EnumSchema, :foo)
      end
    end
  end
end
