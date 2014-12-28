defmodule Ecto.Model.SchemaTest do
  use ExUnit.Case, async: true

  defmodule MyModel do
    use Ecto.Model

    schema "mymodel" do
      field :name,  :string, default: "eric"
      field :email, :string, uniq: true
      field :temp,  :any, default: "temp", virtual: true
      field :array, {:array, :string}
      belongs_to :comment, Comment
    end

    def model_from do
      from(c in __MODULE__, where: c.name == nil)
    end
  end

  test "imports Ecto.Query functions" do
    assert %Ecto.Query{} = MyModel.model_from
  end

  test "schema metadata" do
    assert MyModel.__schema__(:source)             == "mymodel"
    assert MyModel.__schema__(:fields)             == [:id, :name, :email, :array, :comment_id]
    assert MyModel.__schema__(:field, :id)         == :integer
    assert MyModel.__schema__(:field, :name)       == :string
    assert MyModel.__schema__(:field, :email)      == :string
    assert MyModel.__schema__(:field, :array)      == {:array, :string}
    assert MyModel.__schema__(:field, :comment_id) == :integer
  end

  test "assign metadata" do
    assert MyModel.__assign__ ==
           %{name: :string, email: :string, array: {:array, :string},
             comment_id: :integer, temp: :any}
  end

  defmodule DefaultModel do
    @schema_defaults primary_key: {:uuid, :string, []},
                     foreign_key_type: :string
    use Ecto.Model

    schema "users" do
      field :name
      belongs_to :comment, Comment
    end
  end

  test "uses @schema_defauls" do
    assert %DefaultModel{uuid: "abc"}.uuid == "abc"
    assert DefaultModel.__schema__(:field, :comment_id) == :string
  end

  ## Errors

  test "field name clash" do
    assert_raise ArgumentError, "field/association `name` is already set on schema", fn ->
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
    assert_raise ArgumentError, "unknown field type `{:apa}`", fn ->
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

  test "doesn't fail custom primary key" do
    defmodule ModelDontFailCustomPK do
      use Ecto.Model

      schema "custompk", primary_key: false do
        field :x, :string
        field :pk, :integer, primary_key: true
      end
    end
  end

  ##

  defmodule AssocModel do
    use Ecto.Model

    schema "assocs" do
      has_many :posts, Post
      has_one :author, User
      belongs_to :comment, Comment
    end
  end

  test "associations" do
    assert AssocModel.__schema__(:association, :not_a_field) == nil
    assert AssocModel.__schema__(:fields) == [:id, :comment_id]
  end

  test "has_many association" do
    assert AssocModel.__schema__(:association, :posts) ==
           %Ecto.Reflections.HasMany{field: :posts, owner: AssocModel,
                                     assoc: Post, key: :id, assoc_key: :assoc_model_id}

    posts = (%AssocModel{}).posts
    assert %Ecto.Associations.NotLoaded{} = posts
    assert inspect(posts) == "#Ecto.Associations.NotLoaded<association :posts is not loaded>"
  end

  test "has_one association" do
    assert AssocModel.__schema__(:association, :author) ==
           %Ecto.Reflections.HasOne{field: :author, owner: AssocModel,
                                    assoc: User, key: :id, assoc_key: :assoc_model_id}

    author = (%AssocModel{}).author
    assert %Ecto.Associations.NotLoaded{} = author
    assert inspect(author) == "#Ecto.Associations.NotLoaded<association :author is not loaded>"
  end

  test "belongs_to association" do
    assert AssocModel.__schema__(:association, :comment) ==
           %Ecto.Reflections.BelongsTo{field: :comment, owner: AssocModel,
                                       assoc: Comment, key: :comment_id, assoc_key: :id}

    comment = (%AssocModel{}).comment
    assert %Ecto.Associations.NotLoaded{} = comment
    assert inspect(comment) == "#Ecto.Associations.NotLoaded<association :comment is not loaded>"
  end

  defmodule ModelAssocOpts do
    use Ecto.Model

    @schema_defaults foreign_key_type: :string

    schema "assoc", primary_key: {:pk, :integer, []} do
      has_many :posts, Post, references: :pk, foreign_key: :fk
      has_one :author, User, references: :pk, foreign_key: :fk
      belongs_to :permalink1, Permalink, references: :pk, foreign_key: :fk
      belongs_to :permalink2, Permalink, references: :pk, type: :uuid
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
    refl = ModelAssocOpts.__schema__(:association, :permalink1)
    assert :pk == refl.assoc_key
    assert :fk == refl.key

    refl = ModelAssocOpts.__schema__(:association, :permalink2)
    assert :pk == refl.assoc_key
    assert :permalink2_id == refl.key

    assert ModelAssocOpts.__schema__(:field, :fk) == :string
    assert ModelAssocOpts.__schema__(:field, :permalink2_id) == :uuid
  end

  test "references option has to match a field on model" do
    message = "model does not have the field :pk used by association :posts, " <>
              "please set the :references option accordingly"
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
