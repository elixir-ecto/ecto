defmodule Ecto.EntityTest do
  use ExUnit.Case, async: true

  defmodule MyEntity do
    use Ecto.Entity

    field :name, :string, default: "eric"
    field :email, :string, uniq: true
    field :temp, :virtual, default: "temp"
    field :array, { :array, :string }

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
      { :id, [type: :integer] },
      { :name, [type: :string] },
      { :email, [type: :string, uniq: true] },
      { :array, [type: { :array, :string }] }
    ]

    assert MyEntity.__entity__(:field_names) == [:id, :name, :email, :array]
    assert MyEntity.__entity__(:field, :id) == fields[:id]
    assert MyEntity.__entity__(:field, :name) == fields[:name]
    assert MyEntity.__entity__(:field, :email) == fields[:email]
    assert MyEntity.__entity__(:field_type, :id) == fields[:id][:type]
    assert MyEntity.__entity__(:field_type, :name) == fields[:name][:type]
    assert MyEntity.__entity__(:field_type, :email) == fields[:email][:type]
    assert MyEntity.__entity__(:field_type, :array) == fields[:array][:type]

    assert MyEntity.__record__(:fields) ==
           [model: nil, id: nil, name: "eric", email: nil, temp: "temp", array: nil]
  end

  test "primary_key accessor" do
    entity = MyEntity[id: 123]
    assert 123 == entity.primary_key
    assert MyEntity[id: 124] = entity.primary_key(124)
    assert MyEntity[id: 125] = entity.update_primary_key(&(&1 + 2))
  end

  test "field name clash" do
    assert_raise ArgumentError, "field `name` was already set on entity", fn ->
      defmodule EntityFieldNameClash do
        use Ecto.Entity

        field :name, :string
        field :name, :integer
      end
    end
  end

  test "invalid field type" do
    assert_raise ArgumentError, "`{:apa}` is not a valid field type", fn ->
      defmodule EntitInvalidFieldType do
        use Ecto.Entity

        field :name, { :apa }
      end
    end
  end

  defmodule MyEntityNoPK do
    use Ecto.Entity, primary_key: false

    field :x, :string
  end

  test "no primary key" do
    assert MyEntityNoPK.__record__(:fields) == [model: nil, x: nil]
    assert MyEntityNoPK.__entity__(:field_names) == [:x]

    entity = MyEntityNoPK[x: "123"]
    assert entity.primary_key == nil
    assert entity.primary_key("abc") == entity
    assert entity.update_primary_key(&(&1 <> "abc")) == entity
  end

  defmodule EntityCustomPK do
    use Ecto.Entity, primary_key: { :pk, :integer, [] }
    field :x, :string
  end

  test "custom primary key" do
    assert EntityCustomPK.__record__(:fields) == [model: nil, pk: nil, x: nil]
    assert EntityCustomPK.__entity__(:field_names) == [:pk, :x]

    entity = EntityCustomPK[pk: "123"]
    assert entity.primary_key == "123"
    assert EntityCustomPK[pk: "abc"] = entity.primary_key("abc")
    assert EntityCustomPK[pk: "123abc"] = entity.update_primary_key(&(&1 <> "abc"))
  end

  test "fail custom primary key" do
    assert_raise ArgumentError, "primary key already defined as `id`", fn ->
      defmodule EntityFailCustomPK do
        use Ecto.Entity

        field :x, :string
        field :pk, :integer, primary_key: true
      end
    end
  end

  test "dont fail custom primary key" do
    defmodule EntityDontFailCustomPK do
      use Ecto.Entity, primary_key: false

      field :x, :string
      field :pk, :integer, primary_key: true
    end
  end

  defmodule EntityAssocs do
    use Ecto.Entity, model: Assocs

    has_many :posts, Post
    has_one :author, User
    belongs_to :comment, Comment
  end

  test "associations" do
    assert EntityAssocs.__entity__(:association, :not_a_field) == nil
    assert EntityAssocs.__record__(:fields) |> Keyword.keys ==
      [:model, :id, :__posts__, :__author__, :comment_id, :__comment__]
    assert EntityAssocs.__entity__(:field_names) == [:id, :comment_id]
  end

  test "has_many association" do
    refl = Ecto.Reflections.HasMany[field: :"__posts__", owner: EntityAssocs,
                                    associated: Post, key: :id, assoc_key: :assocs_id]
    assert refl == EntityAssocs.__entity__(:association, :posts)

    r = EntityAssocs[id: 1]
    assoc = r.posts
    assert assoc.__assoc__(:name) == :posts
    assert assoc.__assoc__(:target) == EntityAssocs
    assert assoc.__assoc__(:primary_key) == r.id

    assert_raise FunctionClauseError, fn ->
      r.posts(:test)
    end

    r = r.posts([:test])
    assert [:test] = r.posts.to_list
    assert 1 = r.id

    r = EntityAssocs[]
    message = "cannot access association when its primary key is not set on the entity"
    assert_raise ArgumentError, message, fn ->
      r.posts
    end
  end

  test "has_one association" do
    refl = Ecto.Reflections.HasOne[field: :"__author__", owner: EntityAssocs,
                                   associated: User, key: :id, assoc_key: :assocs_id]
    assert refl == EntityAssocs.__entity__(:association, :author)

    r = EntityAssocs[id: 2]
    assoc = r.author
    assert assoc.__assoc__(:name) == :author
    assert assoc.__assoc__(:target) == EntityAssocs

    assert_raise FunctionClauseError, fn ->
      r.author(:test)
    end

    r = r.author({ User })
    assert { User } = r.author.get
    assert 2 = r.id

    r = EntityAssocs[]
    message = "cannot access association when its primary key is not set on the entity"
    assert_raise ArgumentError, message, fn ->
      r.author
    end
  end

  test "belongs_to association" do
    refl = Ecto.Reflections.BelongsTo[field: :"__comment__", owner: EntityAssocs,
                                      associated: Comment, key: :comment_id, assoc_key: :id]
    assert refl == EntityAssocs.__entity__(:association, :comment)

    assert EntityAssocs.__entity__(:field, :comment_id) == [type: :integer]

    r = EntityAssocs[id: 3]
    assoc = r.comment
    assert assoc.__assoc__(:name) == :comment
    assert assoc.__assoc__(:target) == EntityAssocs

    assert_raise FunctionClauseError, fn ->
      r.comment(:test)
    end

    r = r.comment({ Comment })
    assert { Comment } = r.comment.get
    assert 3 = r.id
  end

  test "belongs_to association foreign_key type" do
    defmodule ForeignKeyType do
      use Ecto.Entity
      belongs_to :comment, Comment, type: :datetime
    end

    defmodule DefaultForeignKeyType do
      @queryable_defaults foreign_key_type: :string
      use Ecto.Model

      queryable "defaults" do
        ## :type option overrides any @queryable_defaults
        belongs_to :comment, Comment, type: :interval
      end
    end

    assert ForeignKeyType.__entity__(:field, :comment_id) == [type: :datetime]
    assert DefaultForeignKeyType.Entity.__entity__(:field, :comment_id) == [type: :interval]
  end

  test "association needs foreign_key option if no model" do
    assert_raise ArgumentError, fn ->
      defmodule EntityAssocsNoModel do
        use Ecto.Entity

        has_many :posts, Post
        has_one :author, User
      end
    end

    defmodule EntityAssocsNoModel do
      use Ecto.Entity

      has_many :posts, Post, foreign_key: :"test"
      has_one :author, User, foreign_key: :"test"
    end
  end

  defmodule EntityAssocOpts do
    use Ecto.Entity, model: AssocOpts, primary_key: { :pk, :integer, [] }

    has_many :posts, Post, references: :pk, foreign_key: :fk
    has_one :author, User, references: :pk, foreign_key: :fk
    belongs_to :permalink, Permalink, references: :pk, foreign_key: :fk
    belongs_to :permalink2, Permalink, references: :pk
  end

  test "has_many options" do
    refl = EntityAssocOpts.__entity__(:association, :posts)
    assert :pk == refl.key
    assert :fk == refl.assoc_key
  end

  test "has_one options" do
    refl = EntityAssocOpts.__entity__(:association, :author)
    assert :pk == refl.key
    assert :fk == refl.assoc_key
  end

  test "belongs_to options" do
    refl = EntityAssocOpts.__entity__(:association, :permalink)
    assert :pk == refl.assoc_key
    assert :fk == refl.key

    refl = EntityAssocOpts.__entity__(:association, :permalink2)
    assert :pk == refl.assoc_key
    assert :permalink2_id == refl.key
  end

  test "references option has to match a field on entity" do
    message = "`references` option on association doesn't match any field on the entity"
    assert_raise ArgumentError, message, fn ->
      defmodule EntityPkAssocMisMatch do
        use Ecto.Entity, model: PkAssocMisMatch

        has_many :posts, Post, references: :pk
        has_one :author, User, references: :pk
      end
    end
  end
end
