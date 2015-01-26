defmodule Ecto.SchemaTest do
  use ExUnit.Case, async: true

  defmodule MyModel do
    use Ecto.Model

    schema "mymodel" do
      field :name,  :string, default: "eric"
      field :email, :string, uniq: true
      field :temp,  :any, default: "temp", virtual: true
      field :array, {:array, :string}
      belongs_to :comment, Comment
      belongs_to :permalink, Permalink, auto_field: false
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

  test "changeset metadata" do
    assert MyModel.__changeset__ ==
           %{name: :string, email: :string, array: {:array, :string},
             comment_id: :integer, temp: :any, id: :integer}
  end

  test "skip field with auto_field false" do
    refute MyModel.__schema__(:field, :permalink_id)
  end

  defmodule SchemaModel do
    use Ecto.Model

    @primary_key {:uuid, :string, []}
    @foreign_key_type :string

    schema "users" do
      field :name
      belongs_to :comment, Comment
    end
  end

  test "uses schema attributes" do
    assert %SchemaModel{uuid: "abc"}.uuid == "abc"
    assert SchemaModel.__schema__(:field, :comment_id) == :string
  end

  test "primary key" do
    assert Ecto.Model.primary_key(%MyModel{}) == nil
    assert Ecto.Model.primary_key(%MyModel{id: "hello"}) == "hello"
  end

  test "custom primary key" do
    assert Ecto.Model.primary_key(%SchemaModel{}) == nil
    assert Ecto.Model.primary_key(%SchemaModel{uuid: "hello"}) == "hello"
  end

  test "has __state__ attribute" do
    assert %SchemaModel{}.__state__ == :built
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
    assert_raise ArgumentError, "invalid field type `{:apa}`", fn ->
      defmodule ModelInvalidFieldType do
        use Ecto.Model

        schema "invalidtype" do
          field :name, {:apa}
        end
      end
    end

    assert_raise ArgumentError, "invalid or unknown field type `OMG`", fn ->
      defmodule ModelInvalidFieldType do
        use Ecto.Model

        schema "invalidtype" do
          field :name, OMG
        end
      end
    end
  end

  test "fail invalid schema" do
    assert_raise ArgumentError, "schema source must be a string, got: :hello", fn ->
      defmodule SchemaFail do
        use Ecto.Model

        schema :hello do
          field :x, :string
          field :pk, :integer, primary_key: true
        end
      end
    end
  end

  test "fail invalid default" do
    assert_raise ArgumentError, "schema source must be a string, got: :hello", fn ->
      defmodule SchemaFail do
        use Ecto.Model

        schema :hello do
          field :x, :string, default: 13
        end
      end
    end
  end

  ## Associations

  defmodule AssocModel do
    use Ecto.Model

    schema "assocs" do
      has_many :posts, Post
      has_one :author, User
      belongs_to :comment, Comment
      has_many :comment_authors, through: [:comment, :authors]
      has_one :comment_main_author, through: [:comment, :main_author]
    end
  end

  test "associations" do
    assert AssocModel.__schema__(:association, :not_a_field) == nil
    assert AssocModel.__schema__(:fields) == [:id, :comment_id]
  end

  test "has_many association" do
    assert AssocModel.__schema__(:association, :posts) ==
           %Ecto.Associations.Has{field: :posts, owner: AssocModel, cardinality: :many,
                                  assoc: Post, owner_key: :id, assoc_key: :assoc_model_id}

    posts = (%AssocModel{}).posts
    assert %Ecto.Associations.NotLoaded{} = posts
    assert inspect(posts) == "#Ecto.Associations.NotLoaded<association :posts is not loaded>"
  end

  test "has_many through association" do
    assert AssocModel.__schema__(:association, :comment_authors) ==
           %Ecto.Associations.HasThrough{field: :comment_authors, owner: AssocModel, cardinality: :many,
                                         through: [:comment, :authors], owner_key: :comment_id}

    authors = (%AssocModel{}).comment_authors
    assert %Ecto.Associations.NotLoaded{} = authors
    assert inspect(authors) == "#Ecto.Associations.NotLoaded<association :comment_authors is not loaded>"
  end

  test "has_one association" do
    assert AssocModel.__schema__(:association, :author) ==
           %Ecto.Associations.Has{field: :author, owner: AssocModel, cardinality: :one,
                                  assoc: User, owner_key: :id, assoc_key: :assoc_model_id}

    author = (%AssocModel{}).author
    assert %Ecto.Associations.NotLoaded{} = author
    assert inspect(author) == "#Ecto.Associations.NotLoaded<association :author is not loaded>"
  end

  test "has_one through association" do
    assert AssocModel.__schema__(:association, :comment_main_author) ==
           %Ecto.Associations.HasThrough{field: :comment_main_author, owner: AssocModel, cardinality: :one,
                                         through: [:comment, :main_author], owner_key: :comment_id}

    author = (%AssocModel{}).comment_main_author
    assert %Ecto.Associations.NotLoaded{} = author
    assert inspect(author) == "#Ecto.Associations.NotLoaded<association :comment_main_author is not loaded>"
  end

  test "belongs_to association" do
    assert AssocModel.__schema__(:association, :comment) ==
           %Ecto.Associations.BelongsTo{field: :comment, owner: AssocModel, cardinality: :one,
                                        assoc: Comment, owner_key: :comment_id, assoc_key: :id}

    comment = (%AssocModel{}).comment
    assert %Ecto.Associations.NotLoaded{} = comment
    assert inspect(comment) == "#Ecto.Associations.NotLoaded<association :comment is not loaded>"
  end

  defmodule ModelAssocOpts do
    use Ecto.Model

    @primary_key {:pk, :integer, []}
    @foreign_key_type :string
    schema "assoc" do
      has_many :posts, Post, references: :pk, foreign_key: :fk
      has_one :author, User, references: :pk, foreign_key: :fk
      belongs_to :permalink1, Permalink, references: :pk, foreign_key: :fk
      belongs_to :permalink2, Permalink, references: :pk, type: :uuid
    end
  end

  test "has_many options" do
    refl = ModelAssocOpts.__schema__(:association, :posts)
    assert :pk == refl.owner_key
    assert :fk == refl.assoc_key
  end

  test "has_one options" do
    refl = ModelAssocOpts.__schema__(:association, :author)
    assert :pk == refl.owner_key
    assert :fk == refl.assoc_key
  end

  test "belongs_to options" do
    refl = ModelAssocOpts.__schema__(:association, :permalink1)
    assert :fk == refl.owner_key
    assert :pk == refl.assoc_key

    refl = ModelAssocOpts.__schema__(:association, :permalink2)
    assert :permalink2_id == refl.owner_key
    assert :pk == refl.assoc_key

    assert ModelAssocOpts.__schema__(:field, :fk) == :string
    assert ModelAssocOpts.__schema__(:field, :permalink2_id) == :uuid
  end

  test "has_* references option has to match a field on model" do
    message = ~r"model does not have the field :pk used by association :posts"
    assert_raise ArgumentError, message, fn ->
      defmodule ModelPkAssocMisMatch do
        use Ecto.Model

        schema "assoc" do
          has_many :posts, Post, references: :pk
        end
      end
    end
  end

  test "has_* through has to match an association on model" do
    message = ~r"model does not have the association :whatever used by association :posts"
    assert_raise ArgumentError, message, fn ->
      defmodule ModelPkAssocMisMatch do
        use Ecto.Model

        schema "assoc" do
          has_many :posts, through: [:whatever, :works]
        end
      end
    end
  end
end
