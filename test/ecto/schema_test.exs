Code.require_file "../../integration_test/support/types.exs", __DIR__

defmodule Ecto.SchemaTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  defmodule Model do
    use Ecto.Schema

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
  end

  test "schema metadata" do
    assert Model.__schema__(:source)             == "mymodel"
    assert Model.__schema__(:prefix)             == nil
    assert Model.__schema__(:fields)             == [:id, :name, :email, :count, :array, :uuid, :comment_id]
    assert Model.__schema__(:read_after_writes)  == [:email, :count]
    assert Model.__schema__(:primary_key)        == [:id]
    assert Model.__schema__(:autogenerate_id)    == {:id, :id}
  end

  test "types metadata" do
    assert Model.__schema__(:types) ==
           [id: :id, name: :string, email: :string, count: :decimal,
            array: {:array, :string}, uuid: Ecto.UUID, comment_id: :id]
    assert Model.__schema__(:type, :id)         == :id
    assert Model.__schema__(:type, :name)       == :string
    assert Model.__schema__(:type, :email)      == :string
    assert Model.__schema__(:type, :array)      == {:array, :string}
    assert Model.__schema__(:type, :comment_id) == :id
  end

  test "changeset metadata" do
    assert Model.__changeset__ |> Map.drop([:comment, :permalink]) ==
           %{name: :string, email: :string, count: :decimal, array: {:array, :string},
             comment_id: :id, temp: :any, id: :id, uuid: Ecto.UUID}
  end

  test "skip field with define_field false" do
    refute Model.__schema__(:type, :permalink_id)
  end

  test "primary key" do
    assert Ecto.primary_key(%Model{}) == [id: nil]
    assert Ecto.primary_key(%Model{id: "hello"}) == [id: "hello"]
  end

  test "reads and writes meta" do
    model = %Model{}
    assert model.__meta__.source == {nil, "mymodel"}
    model = Ecto.put_meta(model, source: "new_model")
    assert model.__meta__.source == {nil, "new_model"}
    model = Ecto.put_meta(model, prefix: "prefix")
    assert model.__meta__.source == {"prefix", "new_model"}
    model = Ecto.put_meta(model, source: "mymodel")
    assert model.__meta__.source == {"prefix", "mymodel"}
    assert Ecto.get_meta(model, :prefix) == "prefix"
    assert Ecto.get_meta(model, :source) == "mymodel"

    model = Ecto.put_meta(model, context: "foobar", state: :loaded)
    assert model.__meta__.state == :loaded
    assert model.__meta__.context == "foobar"
    assert Ecto.get_meta(model, :state) == :loaded
    assert Ecto.get_meta(model, :context) == "foobar"
  end

  test "inspects metadata" do
    model = %Model{}
    assert inspect(model.__meta__) == "#Ecto.Schema.Metadata<:built>"
  end

  test "default of array field is not []" do
     assert %Model{}.array == nil
  end

  defmodule SchemaModel do
    use Ecto.Schema

    @primary_key {:perm, Custom.Permalink, autogenerate: true}
    @foreign_key_type :string

    schema "users" do
      field :name
      capture_io :stderr, fn ->
        belongs_to :comment, Comment
      end
    end
  end

  test "uses schema attributes" do
    assert %SchemaModel{perm: "abc"}.perm == "abc"
    assert SchemaModel.__schema__(:autogenerate_id) == {:perm, :id}
    assert SchemaModel.__schema__(:type, :comment_id) == :string
  end

  test "custom primary key" do
    assert Ecto.primary_key(%SchemaModel{}) == [perm: nil]
    assert Ecto.primary_key(%SchemaModel{perm: "hello"}) == [perm: "hello"]
  end

  test "has __meta__ field" do
    assert %SchemaModel{}.__meta__.state == :built
    assert %SchemaModel{}.__meta__.source == {nil, "users"}
    assert SchemaModel.__schema__(:type, :__meta__) == nil
  end

  ## Schema prefix

  defmodule SchemaWithPrefix do
    use Ecto.Schema

    @schema_prefix "tenant"
    schema "company" do
      field :name
    end
  end

  test "schema prefix metadata" do
    assert SchemaWithPrefix.__schema__(:source) == "company"
    assert SchemaWithPrefix.__schema__(:prefix) == "tenant"
    assert %SchemaWithPrefix{}.__meta__.source == {"tenant", "company"}
  end

  test "schema prefix in queries" do
    import Ecto.Query

    query = from(SchemaWithPrefix, select: 1)
    assert query.prefix == "tenant"

    query = from({"another_company", SchemaWithPrefix}, select: 1)
    assert query.prefix == "tenant"

    from = SchemaWithPrefix
    query = from(from, select: 1)
    assert query.prefix == "tenant"

    from = {"another_company", SchemaWithPrefix}
    query = from(from, select: 1)
    assert query.prefix == "tenant"
  end

  test "updates meta prefix with put_meta" do
    model = %SchemaWithPrefix{}
    assert model.__meta__.source == {"tenant", "company"}
    model = Ecto.put_meta(model, source: "new_company")
    assert model.__meta__.source == {"tenant", "new_company"}
    model = Ecto.put_meta(model, prefix: "prefix")
    assert model.__meta__.source == {"prefix", "new_company"}
    model = Ecto.put_meta(model, prefix: nil)
    assert model.__meta__.source == {nil, "new_company"}
  end

  ## Errors

  test "complains when a schema is not defined" do
    assert_raise RuntimeError, ~r"does not define a schema", fn ->
      defmodule Sample do
        use Ecto.Schema
      end
    end
  end

  test "field name clash" do
    assert_raise ArgumentError, "field/association :name is already set on schema", fn ->
      defmodule SchemaFieldNameClash do
        use Ecto.Schema

        schema "clash" do
          field :name, :string
          field :name, :integer
        end
      end
    end
  end

  test "invalid field type" do
    assert_raise ArgumentError, "invalid type {:apa} for field :name", fn ->
      defmodule SchemaInvalidFieldType do
        use Ecto.Schema

        schema "invalidtype" do
          field :name, {:apa}
        end
      end
    end

    assert_raise ArgumentError, "invalid or unknown type OMG for field :name", fn ->
      defmodule SchemaInvalidFieldType do
        use Ecto.Schema

        schema "invalidtype" do
          field :name, OMG
        end
      end
    end
  end

  test "raises helpful error for :datetime" do
    assert_raise ArgumentError, ~r/Maybe you meant to use Ecto.DateTime\?/, fn ->
      defmodule SchemaInvalidFieldType do
        use Ecto.Schema

        schema "invalidtype" do
          field :published_at, :datetime
        end
      end
    end
  end

  test "raises helpful error for :date" do
    assert_raise ArgumentError, ~r/Maybe you meant to use Ecto.Date\?/, fn ->
      defmodule SchemaInvalidFieldType do
        use Ecto.Schema

        schema "invalidtype" do
          field :published_on, :date
        end
      end
    end
  end

  test "raises helpful error for :time" do
    assert_raise ArgumentError, ~r/Maybe you meant to use Ecto.Time\?/, fn ->
      defmodule SchemaInvalidFieldType do
        use Ecto.Schema

        schema "invalidtype" do
          field :published_time, :time
        end
      end
    end
  end

  test "raises helpful error for :uuid" do
    assert_raise ArgumentError, ~r/Maybe you meant to use Ecto.UUID\?/, fn ->
      defmodule SchemaInvalidFieldType do
        use Ecto.Schema

        schema "invalidtype" do
          field :author_id, :uuid
        end
      end
    end
  end

  test "fail invalid schema" do
    assert_raise ArgumentError, "schema source must be a string, got: :hello", fn ->
      defmodule SchemaFail do
        use Ecto.Schema

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
        use Ecto.Schema

        schema "hello" do
          field :x, :string, default: 13
        end
      end
    end
  end

  test "fail invalid autogenerate" do
    assert_raise ArgumentError,
                 "field :x does not support :autogenerate because it uses a primitive type :string", fn ->
      defmodule AutogenerateFail do
        use Ecto.Schema

        schema "hello" do
          field :x, :string, autogenerate: true
        end
      end
    end

    assert_raise ArgumentError,
                 "field :x does not support :autogenerate because " <>
                 "it uses a custom type Ecto.DateTime that does not define generate/0", fn ->
      defmodule AutogenerateFail do
        use Ecto.Schema

        schema "hello" do
          field :x, Ecto.DateTime, autogenerate: true
        end
      end
    end

    assert_raise ArgumentError,
                 "only primary keys allow :autogenerate for type :id, " <>
                 "field :x is not a primary key", fn ->
      defmodule AutogenerateFail do
        use Ecto.Schema

        schema "hello" do
          field :x, :id, autogenerate: true
        end
      end
    end

    assert_raise ArgumentError,
                 "cannot mark the same field as autogenerate and read_after_writes", fn ->
      defmodule AutogenerateFail do
        use Ecto.Schema

        schema "hello" do
          field :x, Ecto.UUID, autogenerate: true, read_after_writes: true
        end
      end
    end
  end

  ## Associations

  defmodule AssocModel do
    use Ecto.Schema

    schema "assocs" do
      has_many :posts, Post
      has_one :author, User
      belongs_to :comment, Comment
      has_many :comment_authors, through: [:comment, :authors]
      has_one :comment_main_author, through: [:comment, :main_author]
      has_many :emails, {"users_emails", Email}, on_replace: :delete
      has_one :profile, {"users_profiles", Profile}
      belongs_to :summary, {"post_summary", Summary}
    end
  end

  test "associations" do
    assert AssocModel.__schema__(:association, :not_a_field) == nil
    assert AssocModel.__schema__(:fields) == [:id, :comment_id, :summary_id]
  end

  test "has_many association" do
    struct =
      %Ecto.Association.Has{field: :posts, owner: AssocModel, cardinality: :many, on_delete: :nothing,
                            related: Post, owner_key: :id, related_key: :assoc_model_id, queryable: Post,
                            on_replace: :raise}

    assert AssocModel.__schema__(:association, :posts) == struct
    assert AssocModel.__changeset__.posts == {:assoc, struct}

    posts = (%AssocModel{}).posts
    assert %Ecto.Association.NotLoaded{} = posts
    assert inspect(posts) == "#Ecto.Association.NotLoaded<association :posts is not loaded>"
  end

  test "has_many association via {source model}" do
    struct =
      %Ecto.Association.Has{field: :emails, owner: AssocModel, cardinality: :many, on_delete: :nothing,
                            related: Email, owner_key: :id, related_key: :assoc_model_id,
                            queryable: {"users_emails", Email}, on_replace: :delete}

    assert AssocModel.__schema__(:association, :emails) == struct
    assert AssocModel.__changeset__.emails == {:assoc, struct}

    posts = (%AssocModel{}).posts
    assert %Ecto.Association.NotLoaded{__cardinality__: :many} = posts
    assert inspect(posts) == "#Ecto.Association.NotLoaded<association :posts is not loaded>"
  end

  test "has_many through association" do
    assert AssocModel.__schema__(:association, :comment_authors) ==
           %Ecto.Association.HasThrough{field: :comment_authors, owner: AssocModel, cardinality: :many,
                                         through: [:comment, :authors], owner_key: :comment_id}

    refute Map.has_key?(AssocModel.__changeset__, :comment_authors)

    authors = (%AssocModel{}).comment_authors
    assert %Ecto.Association.NotLoaded{} = authors
    assert inspect(authors) == "#Ecto.Association.NotLoaded<association :comment_authors is not loaded>"
  end

  test "has_one association" do
    struct =
      %Ecto.Association.Has{field: :author, owner: AssocModel, cardinality: :one, on_delete: :nothing,
                            related: User, owner_key: :id, related_key: :assoc_model_id, queryable: User,
                            on_replace: :raise}

    assert AssocModel.__schema__(:association, :author) == struct
    assert AssocModel.__changeset__.author == {:assoc, struct}

    author = (%AssocModel{}).author
    assert %Ecto.Association.NotLoaded{} = author
    assert inspect(author) == "#Ecto.Association.NotLoaded<association :author is not loaded>"
  end

  test "has_one association via {source, model}" do
    struct =
      %Ecto.Association.Has{field: :profile, owner: AssocModel, cardinality: :one, on_delete: :nothing,
                            related: Profile, owner_key: :id, related_key: :assoc_model_id,
                            queryable: {"users_profiles", Profile}, on_replace: :raise}

    assert AssocModel.__schema__(:association, :profile) == struct
    assert AssocModel.__changeset__.profile == {:assoc, struct}

    author = (%AssocModel{}).author
    assert %Ecto.Association.NotLoaded{__cardinality__: :one} = author
    assert inspect(author) == "#Ecto.Association.NotLoaded<association :author is not loaded>"
  end

  test "has_one through association" do
    assert AssocModel.__schema__(:association, :comment_main_author) ==
           %Ecto.Association.HasThrough{field: :comment_main_author, owner: AssocModel, cardinality: :one,
                                         through: [:comment, :main_author], owner_key: :comment_id}

    refute Map.has_key?(AssocModel.__changeset__, :comment_main_author)

    author = (%AssocModel{}).comment_main_author
    assert %Ecto.Association.NotLoaded{} = author
    assert inspect(author) == "#Ecto.Association.NotLoaded<association :comment_main_author is not loaded>"
  end

  test "belongs_to association" do
    struct =
      %Ecto.Association.BelongsTo{field: :comment, owner: AssocModel, cardinality: :one,
       related: Comment, owner_key: :comment_id, related_key: :id, queryable: Comment,
       on_replace: :raise, defaults: []}

    assert AssocModel.__schema__(:association, :comment) == struct
    assert AssocModel.__changeset__.comment == {:assoc, struct}

    comment = (%AssocModel{}).comment
    assert %Ecto.Association.NotLoaded{} = comment
    assert inspect(comment) == "#Ecto.Association.NotLoaded<association :comment is not loaded>"
  end

  test "belongs_to association via {source, model}" do
    struct =
      %Ecto.Association.BelongsTo{field: :summary, owner: AssocModel, cardinality: :one,
       related: Summary, owner_key: :summary_id, related_key: :id,
       queryable: {"post_summary", Summary}, on_replace: :raise, defaults: []}

    assert AssocModel.__schema__(:association, :summary) == struct
    assert AssocModel.__changeset__.summary == {:assoc, struct}

    comment = (%AssocModel{}).comment
    assert %Ecto.Association.NotLoaded{} = comment
    assert inspect(comment) == "#Ecto.Association.NotLoaded<association :comment is not loaded>"
  end

  defmodule ModelAssocOpts do
    use Ecto.Schema

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
    assert :fk == refl.related_key
  end

  test "has_one options" do
    refl = ModelAssocOpts.__schema__(:association, :author)
    assert :pk == refl.owner_key
    assert :fk == refl.related_key
  end

  test "belongs_to options" do
    refl = ModelAssocOpts.__schema__(:association, :permalink1)
    assert :fk == refl.owner_key
    assert :pk == refl.related_key

    refl = ModelAssocOpts.__schema__(:association, :permalink2)
    assert :permalink2_id == refl.owner_key
    assert :pk == refl.related_key

    assert ModelAssocOpts.__schema__(:type, :fk) == :string
    assert ModelAssocOpts.__schema__(:type, :permalink2_id) == :string
  end

  test "has_* validates option" do
    assert_raise ArgumentError, "invalid option :unknown for has_many/3", fn ->
      defmodule InvalidHasOption do
        use Ecto.Schema

        schema "assoc" do
          has_many :posts, Post, unknown: :option
        end
      end
    end
  end

  test "has_* references option has to match a field on schema" do
    message = ~r"schema does not have the field :pk used by association :posts"
    assert_raise ArgumentError, message, fn ->
      defmodule ModelPkAssocMisMatch do
        use Ecto.Schema

        schema "assoc" do
          has_many :posts, Post, references: :pk
        end
      end
    end
  end

  test "has_* expects a queryable" do
    message = ~r"association queryable must be a schema or {source, schema}, got: 123"
    assert_raise ArgumentError, message, fn ->
      defmodule QueryableMisMatch do
        use Ecto.Schema

        schema "assoc" do
          has_many :posts, 123
        end
      end
    end
  end

  test "has_* through has to match an association on schema" do
    message = ~r"schema does not have the association :whatever used by association :posts"
    assert_raise ArgumentError, message, fn ->
      defmodule ModelPkAssocMisMatch do
        use Ecto.Schema

        schema "assoc" do
          has_many :posts, through: [:whatever, :works]
        end
      end
    end
  end

  test "has_* through with schema" do
    message = ~r"When using the :through option, the schema should not be passed as second argument"
    assert_raise ArgumentError, message, fn ->
      defmodule ModelThroughMatch do
        use Ecto.Schema

        schema "assoc" do
          has_many :posts, Post, through: [:whatever, :works]
        end
      end
    end
  end
end
