defmodule Ecto.EntityTest do
  use ExUnit.Case, async: true

  defmodule MyEntity do
    use Ecto.Entity

    dataset "my_entity" do
      field :name, :string, default: "eric"
      field :email, :string, uniq: true
      field :temp, :virtual, default: "temp"
      field :array, { :list, :string }
    end

    def inc_id(__MODULE__[id: id]) do
      id + 1
    end
  end

  test "works like a record" do
    entity = MyEntity.new(id: 0, email: "eric@example.com")
    assert entity.name  == "eric"
    assert entity.email == "eric@example.com"
    assert entity.inc_id  == 1

    MyEntity[email: email] = entity.email("another@example.com")
    assert email == "another@example.com"
  end

  test "metadata" do
    fields = [
      { :id, [type: :integer, primary_key: true] },
      { :name, [type: :string, default: "eric"] },
      { :email, [type: :string, uniq: true] },
      { :array, [type: { :list, :string }] }
    ]

    assert MyEntity.__ecto__(:dataset) == "my_entity"
    assert MyEntity.__ecto__(:field_names) == [:id, :name, :email, :array]
    assert MyEntity.__ecto__(:field, :id) == fields[:id]
    assert MyEntity.__ecto__(:field, :name) == fields[:name]
    assert MyEntity.__ecto__(:field, :email) == fields[:email]
    assert MyEntity.__ecto__(:field_type, :id) == fields[:id][:type]
    assert MyEntity.__ecto__(:field_type, :name) == fields[:name][:type]
    assert MyEntity.__ecto__(:field_type, :email) == fields[:email][:type]
    assert MyEntity.__ecto__(:field_type, :array) == fields[:array][:type]

    assert MyEntity.__record__(:fields) ==
           [id: nil, name: "eric", email: nil, temp: "temp", array: nil]
  end

  test "primary_key accessor" do
    entity = MyEntity[id: 123]
    assert 123 == entity.primary_key
    assert MyEntity[id: 124] = entity.primary_key(124)
    assert MyEntity[id: 125] = entity.update_primary_key(&1 + 2)
  end

  test "field name clash" do
    assert_raise ArgumentError, "field `name` was already set on entity", fn ->
      defmodule EntityFieldNameClash do
        use Ecto.Entity

        dataset :entity do
          field :name, :string
          field :name, :integer
        end
      end
    end
  end

  test "invalid field type" do
    assert_raise ArgumentError, "`{:apa}` is not a valid field type", fn ->
      defmodule EntitInvalidFieldType do
        use Ecto.Entity

        dataset :entity do
          field :name, { :apa }
        end
      end
    end
  end

  defmodule MyEntityNoPK do
    use Ecto.Entity

    dataset "my_entity", nil do
      field :x, :string
    end
  end

  test "no primary key" do
    assert MyEntityNoPK.__record__(:fields) == [x: nil]
    assert MyEntityNoPK.__ecto__(:field_names) == [:x]

    entity = MyEntityNoPK[x: "123"]
    assert entity.primary_key == nil
    assert entity.primary_key("abc") == entity
    assert entity.update_primary_key(&1 <> "abc") == entity
  end

  defmodule EntityCustomPK do
    use Ecto.Entity

    dataset "my_entity", nil do
      field :x, :string
      field :pk, :integer, primary_key: true
    end
  end

  test "custom primary key" do
    assert EntityCustomPK.__record__(:fields) == [x: nil, pk: nil]
    assert EntityCustomPK.__ecto__(:field_names) == [:x, :pk]

    entity = EntityCustomPK[pk: "123"]
    assert entity.primary_key == "123"
    assert EntityCustomPK[pk: "abc"] = entity.primary_key("abc")
    assert EntityCustomPK[pk: "123abc"] = entity.update_primary_key(&1 <> "abc")
  end

  test "fail custom primary key" do
    message = "there can only be one primary key, a custom primary key " <>
      "requires the default to be disabled, see `Ecto.Entity.dataset`"

    assert_raise ArgumentError, message, fn ->
      defmodule EntityFailCustomPK do
        use Ecto.Entity

        dataset "my_entity" do
          field :x, :string
          field :pk, :integer, primary_key: true
        end
      end
    end
  end
end
