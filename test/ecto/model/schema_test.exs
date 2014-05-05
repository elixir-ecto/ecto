defmodule Ecto.Model.SchemaTest do
  use ExUnit.Case, async: true

  defmodule User do
    use Ecto.Model

    schema "users" do
      # Type defaults to string
      field :name
    end
  end

  defmodule Comment do
    defstruct []
  end

  defmodule DefaultUser do
    @schema_defaults primary_key: {:uuid, :string, []},
                     foreign_key_type: :string
    use Ecto.Model

    schema "users" do
      field :name
      belongs_to :comment, Comment
    end
  end

  test "uses @schema_defauls" do
    assert %DefaultUser{uuid: "abc"}.uuid == "abc"
    assert DefaultUser.__schema__(:field, :comment_id) == [type: :string]
  end

  defmodule MyModel do
    use Ecto.Model

    schema "mymodel" do
      field :name, :string, default: "eric"
      field :email, :string, uniq: true
      field :temp, :virtual, default: "temp"
      field :array, {:array, :string}
    end

    def test_attr(:source), do: @ecto_source

    def model_from do
      from(c in __MODULE__, where: c.name == nil)
    end
  end

  test "imports Ecto.Query functions" do
    assert %Ecto.Query{} = MyModel.model_from
  end

  test "schema attributes" do
    assert MyModel.test_attr(:source) == "mymodel"
  end

  test "metadata" do
    fields = [
      {:id, [type: :integer]},
      {:name, [type: :string]},
      {:email, [type: :string, uniq: true]},
      {:array, [type: {:array, :string}]}
    ]

    assert MyModel.__schema__(:source)             == "mymodel"
    assert MyModel.__schema__(:field_names)        == [:id, :name, :email, :array]
    assert MyModel.__schema__(:field, :id)         == fields[:id]
    assert MyModel.__schema__(:field, :name)       == fields[:name]
    assert MyModel.__schema__(:field, :email)      == fields[:email]
    assert MyModel.__schema__(:field_type, :id)    == fields[:id][:type]
    assert MyModel.__schema__(:field_type, :name)  == fields[:name][:type]
    assert MyModel.__schema__(:field_type, :email) == fields[:email][:type]
    assert MyModel.__schema__(:field_type, :array) == fields[:array][:type]
  end

  test "field name clash" do
    assert_raise ArgumentError, "field `name` was already set on schema", fn ->
      defmodule ModelFieldNameClash do
        use Ecto.Model

        schema "clash" do
          field :name, :string
          field :name, :integer
        end
      end
    end
  end

  test "invalid field type" do
    assert_raise ArgumentError, "`{:apa}` is not a valid field type", fn ->
      defmodule ModelInvalidFieldType do
        use Ecto.Model

        schema "invalidtype" do
          field :name, {:apa}
        end
      end
    end
  end

  test "fail custom primary key" do
    assert_raise ArgumentError, "primary key already defined as `id`", fn ->
      defmodule ModelFailCustomPK do
        use Ecto.Model

        schema "custompk" do
          field :x, :string
          field :pk, :integer, primary_key: true
        end
      end
    end
  end

  test "dont fail custom primary key" do
    defmodule ModelDontFailCustomPK do
      use Ecto.Model

      schema "custompk", primary_key: false do
        field :x, :string
        field :pk, :integer, primary_key: true
      end
    end
  end

  defmodule ModelAssocs do
    use Ecto.Model

    schema "assocs" do
      has_many :posts, Post
      has_one :author, User
      belongs_to :comment, Comment
    end
  end

  test "associations" do
    assert ModelAssocs.__schema__(:association, :not_a_field) == nil
    assert ModelAssocs.__schema__(:field_names) == [:id, :comment_id]
  end

  test "has_many association" do
    refl = Ecto.Reflections.HasMany[field: :posts, owner: ModelAssocs,
                                    associated: Post, key: :id, assoc_key: :modelassocs_id]
    assert refl == ModelAssocs.__schema__(:association, :posts)

    r = %ModelAssocs{}
    assoc = r.posts
    assert assoc.__assoc__(:name) == :posts
    assert assoc.__assoc__(:target) == ModelAssocs
    assert assoc.__assoc__(:primary_key) == r.id
  end

  test "has_one association" do
    refl = Ecto.Reflections.HasOne[field: :author, owner: ModelAssocs,
                                   associated: User, key: :id, assoc_key: :modelassocs_id]
    assert refl == ModelAssocs.__schema__(:association, :author)

    r = %ModelAssocs{}
    assoc = r.author
    assert assoc.__assoc__(:name) == :author
    assert assoc.__assoc__(:target) == ModelAssocs
  end

  test "belongs_to association" do
    refl = Ecto.Reflections.BelongsTo[field: :comment, owner: ModelAssocs,
                                      associated: Comment, key: :comment_id, assoc_key: :id]
    assert refl == ModelAssocs.__schema__(:association, :comment)

    assert ModelAssocs.__schema__(:field, :comment_id) == [type: :integer]

    r = %ModelAssocs{}
    assoc = r.comment
    assert assoc.__assoc__(:name) == :comment
    assert assoc.__assoc__(:target) == ModelAssocs
  end

  test "belongs_to association foreign_key type" do
    defmodule ForeignKeyType do
      use Ecto.Model
      schema "fk" do
        belongs_to :comment, Comment, type: :datetime
      end
    end

    defmodule DefaultForeignKeyType do
      @queryable_defaults foreign_key_type: :string
      use Ecto.Model

      schema "defaults" do
        ## :type option overrides any @queryable_defaults
        belongs_to :comment, Comment, type: :interval
      end
    end

    assert ForeignKeyType.__schema__(:field, :comment_id) == [type: :datetime]
    assert DefaultForeignKeyType.__schema__(:field, :comment_id) == [type: :interval]
  end

  defmodule ModelAssocOpts do
    use Ecto.Model

    schema "assoc", primary_key: {:pk, :integer, []} do
      has_many :posts, Post, references: :pk, foreign_key: :fk
      has_one :author, User, references: :pk, foreign_key: :fk
      belongs_to :permalink, Permalink, references: :pk, foreign_key: :fk
      belongs_to :permalink2, Permalink, references: :pk
    end
  end

  test "has_many options" do
    refl = ModelAssocOpts.__schema__(:association, :posts)
    assert :pk == refl.key
    assert :fk == refl.assoc_key
  end

  test "has_one options" do
    refl = ModelAssocOpts.__schema__(:association, :author)
    assert :pk == refl.key
    assert :fk == refl.assoc_key
  end

  test "belongs_to options" do
    refl = ModelAssocOpts.__schema__(:association, :permalink)
    assert :pk == refl.assoc_key
    assert :fk == refl.key

    refl = ModelAssocOpts.__schema__(:association, :permalink2)
    assert :pk == refl.assoc_key
    assert :permalink2_id == refl.key
  end

  test "references option has to match a field on model" do
    message = "`references` option on association doesn't match any field on the model"
    assert_raise ArgumentError, message, fn ->
      defmodule ModelPkAssocMisMatch do
        use Ecto.Model

        schema "assoc" do
          has_many :posts, Post, references: :pk
          has_one :author, User, references: :pk
        end
      end
    end
  end
end
