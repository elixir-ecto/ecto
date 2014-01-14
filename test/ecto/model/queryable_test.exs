defmodule Ecto.Model.QueryableTest do
  use ExUnit.Case, async: true

  defmodule User do
    use Ecto.Model.Queryable

    queryable "users" do
      # Type defaults to string
      field :name
    end

    def test_attr(:entity), do: @ecto_entity
    def test_attr(:source), do: @ecto_source

    def from_1 do
      from(c in __MODULE__)
    end

    def from_2 do
      from(c in __MODULE__, where: c.name == nil)
    end
  end

  defmodule DefaultUser do
    @queryable_defaults primary_key: { :uuid, :string, [] },
                        foreign_key_type: :string,
                        default_fields: [{ :hello, :integer, default: 1 },
                                         { :override_me, :integer, [overridable?: true,
                                                                    default: 2] }]
    use Ecto.Model.Queryable

    queryable "users" do
      field :name
      field :override_me, :float, default: 1.5
      belongs_to :comment, Comment
    end
  end

  test "imports Ecto.Query functions" do
    assert is_record(User.from_1, Ecto.Query.Query)
    assert is_record(User.from_2, Ecto.Query.Query)
  end

  test "uses @queryable_defaults" do
    assert DefaultUser.new(uuid: "abc").uuid == "abc"
    assert DefaultUser.Entity.__entity__(:field, :comment_id) == [type: :string]
    assert DefaultUser.new().hello == 1
    assert DefaultUser.new().override_me == 1.5
  end

  test "delegates to the given entity" do
    assert is_record(User.new, User.Entity)
    assert is_record(User.new(name: "jose"), User.Entity)
  end

  test "queryable attributes" do
    assert User.test_attr(:entity) == User.Entity
    assert User.test_attr(:source) == "users"
  end

  test "generated model functions" do
    assert User.__model__(:entity) == User.Entity
    assert User.__model__(:source) == "users"
  end
end
