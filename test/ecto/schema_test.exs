defmodule Ecto.SchemaTest do
  use ExUnit.Case, async: true

  defmodule MyModel do
    use Ecto.Model

    schema "mymodel" do
      field :name,  :string, default: "eric"
      field :email, :string, uniq: true, read_after_writes: true
      field :temp,  :any, default: "temp", virtual: true
      field :count, :decimal, read_after_writes: true
      field :array, {:array, :string}
      field :uuid, Ecto.UUID, autogenerate: true
      belongs_to :comment, Comment
      belongs_to :permalink, Permalink, define_field: false
    end

    def model_from do
      from(c in __MODULE__, where: is_nil(c.name))
    end
  end

  test "imports Ecto.Query functions" do
    assert %Ecto.Query{} = MyModel.model_from
  end

  test "schema metadata" do
    assert MyModel.__schema__(:source)             == "mymodel"
    assert MyModel.__schema__(:fields)             == [:id, :name, :email, :count, :array, :uuid, :comment_id]
    assert MyModel.__schema__(:field, :id)         == :id
    assert MyModel.__schema__(:field, :name)       == :string
    assert MyModel.__schema__(:field, :email)      == :string
    assert MyModel.__schema__(:field, :array)      == {:array, :string}
    assert MyModel.__schema__(:field, :comment_id) == :id
    assert MyModel.__schema__(:read_after_writes)  == [:id, :email, :count]
    assert MyModel.__schema__(:primary_key)        == [:id]
    assert MyModel.__schema__(:autogenerate)       == %{uuid: Ecto.UUID}
  end

  test "changeset metadata" do
    assert MyModel.__changeset__ ==
           %{name: :string, email: :string, count: :decimal, array: {:array, :string},
             comment_id: :id, temp: :any, id: :id, uuid: Ecto.UUID}
  end

  test "skip field with define_field false" do
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
    assert Ecto.Model.primary_key(%MyModel{}) == [id: nil]
    assert Ecto.Model.primary_key(%MyModel{id: "hello"}) == [id: "hello"]
  end

  test "custom primary key" do
    assert Ecto.Model.primary_key(%SchemaModel{}) == [uuid: nil]
    assert Ecto.Model.primary_key(%SchemaModel{uuid: "hello"}) == [uuid: "hello"]
  end

  test "has __meta__ attribute" do
    assert %SchemaModel{}.__meta__.state == :built
    assert %SchemaModel{}.__meta__.source == "users"
    meta = %Ecto.Schema.Metadata{source: "users", state: :built}
    assert %SchemaModel{} = %SchemaModel{__meta__: meta}
    assert SchemaModel.__schema__(:field, :__meta__) == nil
  end

  test "updates source with put_source" do
    model = %MyModel{}
    assert model.__meta__.source == "mymodel"
    new_model = Ecto.Model.put_source(model, "new_model")
    assert new_model.__meta__.source == "new_model"
  end

  ## Errors

  test "field name clash" do
    assert_raise ArgumentError, "field/association :name is already set on schema", fn ->
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
    assert_raise ArgumentError, "invalid type {:apa} for field :name", fn ->
      defmodule ModelInvalidFieldType do
        use Ecto.Model

        schema "invalidtype" do
          field :name, {:apa}
        end
      end
    end

    assert_raise ArgumentError, "invalid or unknown type OMG for field :name", fn ->
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
    assert_raise ArgumentError, "invalid default argument `13` for field :x of type :string", fn ->
      defmodule DefaultFail do
        use Ecto.Model

        schema "hello" do
          field :x, :string, default: 13
        end
      end
    end
  end

  test "fail invalid autogenerate default" do
    assert_raise ArgumentError,
                 "field :x does not support :autogenerate because it uses a primitive type :string", fn ->
      defmodule AutogenerateFail do
        use Ecto.Model

        schema "hello" do
          field :x, :string, autogenerate: true
        end
      end
    end

    assert_raise ArgumentError,
                 "field :x does not support :autogenerate because " <>
                 "it uses a custom type Ecto.DateTime that does not define generate/0", fn ->
      defmodule AutogenerateFail do
        use Ecto.Model

        schema "hello" do
          field :x, Ecto.DateTime, autogenerate: true
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
      has_many :emails, {"users_emails", Email}
      has_one :profile, {"users_profiles", Profile}
      belongs_to :summary, {"post_summary", Summary}
    end
  end

  test "associations" do
    assert AssocModel.__schema__(:association, :not_a_field) == nil
    assert AssocModel.__schema__(:fields) == [:id, :comment_id, :summary_id]
  end

  test "has_many association" do
    assert AssocModel.__schema__(:association, :posts) ==
           %Ecto.Association.Has{field: :posts, owner: AssocModel, cardinality: :many,
                                  assoc: Post, owner_key: :id, assoc_key: :assoc_model_id, queryable: Post}

    posts = (%AssocModel{}).posts
    assert %Ecto.Association.NotLoaded{} = posts
    assert inspect(posts) == "#Ecto.Association.NotLoaded<association :posts is not loaded>"
  end

  test "has_many association via {source model}" do
    assert AssocModel.__schema__(:association, :emails) ==
           %Ecto.Association.Has{field: :emails, owner: AssocModel, cardinality: :many,
                                  assoc: Email, owner_key: :id, assoc_key: :assoc_model_id, queryable: {"users_emails", Email}}

    posts = (%AssocModel{}).posts
    assert %Ecto.Association.NotLoaded{__cardinality__: :many} = posts
    assert inspect(posts) == "#Ecto.Association.NotLoaded<association :posts is not loaded>"
  end

  test "has_many through association" do
    assert AssocModel.__schema__(:association, :comment_authors) ==
           %Ecto.Association.HasThrough{field: :comment_authors, owner: AssocModel, cardinality: :many,
                                         through: [:comment, :authors], owner_key: :comment_id}

    authors = (%AssocModel{}).comment_authors
    assert %Ecto.Association.NotLoaded{} = authors
    assert inspect(authors) == "#Ecto.Association.NotLoaded<association :comment_authors is not loaded>"
  end

  test "has_one association" do
    assert AssocModel.__schema__(:association, :author) ==
           %Ecto.Association.Has{field: :author, owner: AssocModel, cardinality: :one,
                                  assoc: User, owner_key: :id, assoc_key: :assoc_model_id, queryable: User}

    author = (%AssocModel{}).author
    assert %Ecto.Association.NotLoaded{} = author
    assert inspect(author) == "#Ecto.Association.NotLoaded<association :author is not loaded>"
  end

  test "has_one association via {source, model}" do
    assert AssocModel.__schema__(:association, :profile) ==
           %Ecto.Association.Has{field: :profile, owner: AssocModel, cardinality: :one,
                                  assoc: Profile, owner_key: :id, assoc_key: :assoc_model_id, queryable: {"users_profiles", Profile}}

    author = (%AssocModel{}).author
    assert %Ecto.Association.NotLoaded{__cardinality__: :one} = author
    assert inspect(author) == "#Ecto.Association.NotLoaded<association :author is not loaded>"
  end

  test "has_one through association" do
    assert AssocModel.__schema__(:association, :comment_main_author) ==
           %Ecto.Association.HasThrough{field: :comment_main_author, owner: AssocModel, cardinality: :one,
                                         through: [:comment, :main_author], owner_key: :comment_id}

    author = (%AssocModel{}).comment_main_author
    assert %Ecto.Association.NotLoaded{} = author
    assert inspect(author) == "#Ecto.Association.NotLoaded<association :comment_main_author is not loaded>"
  end

  test "belongs_to association" do
    assert AssocModel.__schema__(:association, :comment) ==
           %Ecto.Association.BelongsTo{field: :comment, owner: AssocModel, cardinality: :one,
                                        assoc: Comment, owner_key: :comment_id, assoc_key: :id, queryable: Comment}

    comment = (%AssocModel{}).comment
    assert %Ecto.Association.NotLoaded{} = comment
    assert inspect(comment) == "#Ecto.Association.NotLoaded<association :comment is not loaded>"
  end

  test "belongs_to association via {source, model}" do
    assert AssocModel.__schema__(:association, :summary) ==
           %Ecto.Association.BelongsTo{field: :summary, owner: AssocModel, cardinality: :one,
                                        assoc: Summary, owner_key: :summary_id, assoc_key: :id, queryable: {"post_summary", Summary}}

    comment = (%AssocModel{}).comment
    assert %Ecto.Association.NotLoaded{} = comment
    assert inspect(comment) == "#Ecto.Association.NotLoaded<association :comment is not loaded>"
  end

  defmodule ModelAssocOpts do
    use Ecto.Model

    @primary_key {:pk, :integer, []}
    @foreign_key_type :string
    schema "assoc" do
      has_many :posts, Post, references: :pk, foreign_key: :fk
      has_one :author, User, references: :pk, foreign_key: :fk
      belongs_to :permalink1, Permalink, references: :pk, foreign_key: :fk
      belongs_to :permalink2, Permalink, references: :pk, type: :string
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
    assert ModelAssocOpts.__schema__(:field, :permalink2_id) == :string
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

  test "has_* expects a queryable" do
    message = ~r"association queryable must be a model or {source, model}, got: 123"
    assert_raise ArgumentError, message, fn ->
      defmodule QueryableMisMatch do
        use Ecto.Model

        schema "assoc" do
          has_many :posts, 123
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

  test "has_* through with model" do
    message = ~r"When using the :through option, the model should not be passed as second argument"
    assert_raise ArgumentError, message, fn ->
      defmodule ModelThroughMatch do
        use Ecto.Model

        schema "assoc" do
          has_many :posts, Post, through: [:whatever, :works]
        end
      end
    end
  end
end
