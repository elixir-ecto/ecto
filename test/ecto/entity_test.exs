Code.require_file "../test_helper.exs", __DIR__

defmodule Ecto.EntityTest do
  use ExUnit.Case, async: true

  defmodule MyEntity do
    use Ecto.Entity
    table_name :my_entity

    primary_key
    field :name, :string, default: "eric"
    field :email, :string, uniq: true

    def upcased_name(__MODULE__[name: name]) do
      String.upcase(name)
    end
  end

  test "works like a record" do
    entity = MyEntity.new(email: "eric@example.com")
    assert entity.name  == "eric"
    assert entity.email == "eric@example.com"
    assert entity.upcased_name  == "ERIC"

    MyEntity[email: email] = entity.email("another@example.com")
    assert email == "another@example.com"
  end

  test "metadata" do
    fields = [
      { :id, [type: :integer, primary_key: true] },
      { :name, [type: :string, default: "eric"] },
      { :email, [type: :string, uniq: true] }
    ]

    assert MyEntity.__ecto__(:table) == :my_entity
    assert MyEntity.__ecto__(:fields) == fields
    assert MyEntity.__ecto__(:field_names) == [:id, :name, :email]
    assert MyEntity.__ecto__(:field, :id) == fields[:id]
    assert MyEntity.__ecto__(:field, :name) == fields[:name]
    assert MyEntity.__ecto__(:field, :email) == fields[:email]
    assert MyEntity.__ecto__(:field_type, :id) == fields[:id][:type]
    assert MyEntity.__ecto__(:field_type, :name) == fields[:name][:type]
    assert MyEntity.__ecto__(:field_type, :email) == fields[:email][:type]

    assert MyEntity.__record__(:fields) ==
           [id: nil, name: "eric", email: nil]
  end

  test "no table name" do
    message = "no support for dasherize and pluralize yet, a table name is required"
    assert_raise ArgumentError, message, fn ->
      defmodule EntityNoTableName do
        use Ecto.Entity
      end
    end
  end

  test "multiple primary keys" do
    assert_raise ArgumentError, "only one primary key can be set on an entity", fn ->
      defmodule EntityMultiplePrimaryKeys do
        use Ecto.Entity
        table_name :entity
        primary_key
        field :name, :string
        primary_key
      end
    end
  end

  test "field name clash" do
    assert_raise ArgumentError, "field `name` was already set on entity", fn ->
      defmodule EntityFieldNameClash do
        use Ecto.Entity
        table_name :entity
        field :name, :string
        field :name, :integer
      end
    end
  end

  test "invalid field type" do
    assert_raise ArgumentError, "`apa` is not a valid field type", fn ->
      defmodule EntitInvalidFieldType do
        use Ecto.Entity
        table_name :entity
        field :name, :apa
      end
    end
  end
end
