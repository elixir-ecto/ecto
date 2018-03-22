Code.require_file "../../integration_test/support/types.exs", __DIR__

defmodule Ecto.SchemaTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  defmodule Schema do
    use Ecto.Schema

    schema "my schema" do
      field :name,  :string, default: "eric", autogenerate: {String, :upcase, ["eric"]}
      field :email, :string, uniq: true, read_after_writes: true
      field :temp,  :any, default: "temp", virtual: true
      field :count, :decimal, read_after_writes: true, source: :cnt
      field :array, {:array, :string}
      field :uuid, Ecto.UUID, autogenerate: true
      belongs_to :comment, Comment
      belongs_to :permalink, Permalink, define_field: false
    end
  end

  test "schema metadata" do
    assert Schema.__schema__(:source)             == "my schema"
    assert Schema.__schema__(:prefix)             == nil
    assert Schema.__schema__(:fields)             == [:id, :name, :email, :count, :array, :uuid, :comment_id]
    assert Schema.__schema__(:read_after_writes)  == [:email, :count]
    assert Schema.__schema__(:primary_key)        == [:id]
    assert Schema.__schema__(:autogenerate_id)    == {:id, :id, :id}
  end

  test "types metadata" do
    assert Schema.__schema__(:type, :id)         == :id
    assert Schema.__schema__(:type, :name)       == :string
    assert Schema.__schema__(:type, :email)      == :string
    assert Schema.__schema__(:type, :array)      == {:array, :string}
    assert Schema.__schema__(:type, :comment_id) == :id
  end

  test "sources metadata" do
    assert Schema.__schema__(:field_source, :id)         == :id
    assert Schema.__schema__(:field_source, :name)       == :name
    assert Schema.__schema__(:field_source, :email)      == :email
    assert Schema.__schema__(:field_source, :array)      == :array
    assert Schema.__schema__(:field_source, :comment_id) == :comment_id
    assert Schema.__schema__(:field_source, :count)      == :cnt
    assert Schema.__schema__(:field_source, :xyz)        == nil
  end

  test "changeset metadata" do
    assert Schema.__changeset__ |> Map.drop([:comment, :permalink]) ==
           %{name: :string, email: :string, count: :decimal, array: {:array, :string},
             comment_id: :id, temp: :any, id: :id, uuid: Ecto.UUID}
  end

  test "autogenerate metadata (private)" do
    assert Schema.__schema__(:autogenerate) ==
           [name: {String, :upcase, ["eric"]}, uuid: {Ecto.UUID, :autogenerate, []}]
    assert Schema.__schema__(:autoupdate) == []
  end

  test "skip field with define_field false" do
    refute Schema.__schema__(:type, :permalink_id)
  end

  test "primary key operations" do
    assert Ecto.primary_key(%Schema{}) == [id: nil]
    assert Ecto.primary_key(%Schema{id: "hello"}) == [id: "hello"]
  end

  test "reads and writes metadata" do
    schema = %Schema{}
    assert schema.__meta__.source == {nil, "my schema"}
    schema = Ecto.put_meta(schema, source: "new schema")
    assert schema.__meta__.source == {nil, "new schema"}
    schema = Ecto.put_meta(schema, prefix: "prefix")
    assert schema.__meta__.source == {"prefix", "new schema"}
    schema = Ecto.put_meta(schema, source: "my schema")
    assert schema.__meta__.source == {"prefix", "my schema"}
    assert Ecto.get_meta(schema, :prefix) == "prefix"
    assert Ecto.get_meta(schema, :source) == "my schema"
    assert schema.__meta__.schema == Schema

    schema = Ecto.put_meta(schema, context: "foobar", state: :loaded)
    assert schema.__meta__.state == :loaded
    assert schema.__meta__.context == "foobar"
    assert Ecto.get_meta(schema, :state) == :loaded
    assert Ecto.get_meta(schema, :context) == "foobar"
  end

  test "inspects metadata" do
    schema = %Schema{}
    assert inspect(schema.__meta__) == "#Ecto.Schema.Metadata<:built, \"my schema\">"

    schema = Ecto.put_meta %Schema{}, context: <<0>>
    assert inspect(schema.__meta__) == "#Ecto.Schema.Metadata<:built, \"my schema\", <<0>>>"
  end

  test "defaults" do
    assert %Schema{}.name == "eric"
    assert %Schema{}.array == nil
  end

  defmodule CustomSchema do
    use Ecto.Schema

    @primary_key {:perm, Custom.Permalink, autogenerate: true}
    @foreign_key_type :string
    @field_source_mapper fn field -> field |> Atom.to_string |> String.upcase |> String.to_atom() end

    schema "users" do
      field :name
      capture_io :stderr, fn ->
        belongs_to :comment, Comment
      end
      timestamps()
    end
  end

  test "custom schema attributes" do
    assert %CustomSchema{perm: "abc"}.perm == "abc"
    assert CustomSchema.__schema__(:autogenerate_id) == {:perm, :PERM, :id}
    assert CustomSchema.__schema__(:type, :comment_id) == :string
  end

  test "custom primary key" do
    assert Ecto.primary_key(%CustomSchema{}) == [perm: nil]
    assert Ecto.primary_key(%CustomSchema{perm: "hello"}) == [perm: "hello"]
  end

  test "custom field source mapper" do
    assert CustomSchema.__schema__(:field_source, :perm) == :PERM
    assert CustomSchema.__schema__(:field_source, :comment_id) == :COMMENT_ID
    assert CustomSchema.__schema__(:field_source, :inserted_at) == :INSERTED_AT
    assert CustomSchema.__schema__(:field_source, :updated_at) == :UPDATED_AT
  end

  defmodule EmbeddedSchema do
    use Ecto.Schema

    embedded_schema do
      field :name,  :string, default: "eric"
    end
  end

  test "embedded schema" do
    assert EmbeddedSchema.__schema__(:source)          == nil
    assert EmbeddedSchema.__schema__(:prefix)          == nil
    assert EmbeddedSchema.__schema__(:fields)          == [:id, :name]
    assert EmbeddedSchema.__schema__(:primary_key)     == [:id]
    assert EmbeddedSchema.__schema__(:autogenerate_id) == {:id, :id, :binary_id}
  end

  test "embeded schema does not have metadata" do
    refute match?(%{__meta__: _}, %EmbeddedSchema{})
  end

  defmodule CustomEmbeddedSchema do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :name, :string
    end
  end

  test "custom embedded schema" do
    assert CustomEmbeddedSchema.__schema__(:source)      == nil
    assert CustomEmbeddedSchema.__schema__(:prefix)      == nil
    assert CustomEmbeddedSchema.__schema__(:fields)      == [:name]
    assert CustomEmbeddedSchema.__schema__(:primary_key) == []
  end

  defmodule InlineEmbeddedSchema do
    use Ecto.Schema

    schema "inline_embedded_schema" do
      embeds_one :one, One, primary_key: false do
        field :x
      end
      embeds_many :many, Many do
        field :y
      end
    end
  end

  test "inline embedded schema" do
    assert %Ecto.Embedded{related: InlineEmbeddedSchema.One} =
      InlineEmbeddedSchema.__schema__(:embed, :one)
    assert %Ecto.Embedded{related: InlineEmbeddedSchema.Many} =
      InlineEmbeddedSchema.__schema__(:embed, :many)
    assert InlineEmbeddedSchema.One.__schema__(:fields)  == [:x]
    assert InlineEmbeddedSchema.Many.__schema__(:fields) == [:id, :y]
  end

  defmodule Timestamps do
    use Ecto.Schema

    schema "timestamps" do
      timestamps autogenerate: {:m, :f, [:a]}
    end
  end

  test "timestamps autogenerate metadata (private)" do
    assert Timestamps.__schema__(:autogenerate) ==
           [inserted_at: {:m, :f, [:a]}, updated_at: {:m, :f, [:a]}]
    assert Timestamps.__schema__(:autoupdate) ==
           [updated_at: {:m, :f, [:a]}]
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
    schema = %SchemaWithPrefix{}
    assert schema.__meta__.source == {"tenant", "company"}
    schema = Ecto.put_meta(schema, source: "new_company")
    assert schema.__meta__.source == {"tenant", "new_company"}
    schema = Ecto.put_meta(schema, prefix: "prefix")
    assert schema.__meta__.source == {"prefix", "new_company"}
    schema = Ecto.put_meta(schema, prefix: nil)
    assert schema.__meta__.source == {nil, "new_company"}
  end

  ## Composite primary keys

  defmodule SchemaCompositeKeys do
    use Ecto.Schema

    # Extra key without disabling @primary_key
    schema "composite_keys" do
      field :second_id, :id, primary_key: true
      field :name
    end
  end

  # Associative_entity map example:
  # https://en.wikipedia.org/wiki/Associative_entity
  defmodule AssocCompositeKeys do
    use Ecto.Schema

    @primary_key false
    schema "student_course_registers" do
      belongs_to :student, Student, primary_key: true
      belongs_to :course, Course, foreign_key: :course_ref_id, primary_key: true
    end
  end

  test "composite primary keys" do
    assert SchemaCompositeKeys.__schema__(:primary_key) == [:id, :second_id]
    assert AssocCompositeKeys.__schema__(:primary_key) == [:student_id, :course_ref_id]

    c = %SchemaCompositeKeys{id: 1, second_id: 2}
    assert Ecto.primary_key(c) == [id: 1, second_id: 2]
    assert Ecto.primary_key!(c) == [id: 1, second_id: 2]

    sc = %AssocCompositeKeys{student_id: 1, course_ref_id: 2}
    assert Ecto.primary_key!(sc) == [student_id: 1, course_ref_id: 2]
  end

  ## Errors

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
    assert_raise ArgumentError, "invalid or unknown type {:apa} for field :name", fn ->
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

    assert_raise ArgumentError, ~r/schema Ecto.SchemaTest.Schema is not a valid type for field :name/, fn ->
      defmodule SchemaInvalidFieldType do
        use Ecto.Schema

        schema "invalidtype" do
          field :name, Schema
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

  defmodule Post do
    use Ecto.Schema

    import Ecto.Query, only: [from: 2]

    schema "post_assoc" do
      field :score, :integer
    end

    def low_score() do
      from post in __MODULE__,
        where: post.score < 25
    end
  end

  defmodule Comment do
    use Ecto.Schema

    import Ecto.Query, only: [from: 2]

    schema "comment_assoc" do
      field :score, :integer
    end

    def high_score() do
      from comment in __MODULE__,
        where: comment.score > 100
    end
  end

  defmodule User do
    use Ecto.Schema

    import Ecto.Query, only: [from: 2]

    schema "user_assoc" do
      field :score, :integer
    end

    def middle_range_score() do
      from author in __MODULE__,
        where: author.score > 25,
        where: author.score < 75
    end

    def awesome() do
      from author in __MODULE__,
        where: author.score > 1000
    end
  end

  defmodule AssocEditors do
    use Ecto.Schema

    import Ecto.Query, only: [from: 2]

    schema "assoc_join_table" do
      belongs_to :user, User
      belongs_to :assoc, AssocSchema

      field :deleted, :boolean
    end

    def active() do
      from join_row in __MODULE__,
        where: not(join_row.deleted)
    end
  end

  ## Associations

  defmodule AssocSchema do
    use Ecto.Schema

    schema "assocs" do
      has_many :posts, Post
      has_many :low_scoring_posts, Post.low_score()
      has_one :author, User

      has_one :middle_range_author, User.middle_range_score()

      belongs_to :comment, Comment

      belongs_to :high_scoring_comment, Comment.high_score(),
        foreign_key: :comment_id,
        define_field: false

      many_to_many :awesome_editors, User.awesome(), join_through: AssocEditors.active(), on_replace: :delete

      has_many :comment_authors, through: [:comment, :authors]
      has_one :comment_main_author, through: [:comment, :main_author]
      has_many :emails, {"users_emails", Email}, on_replace: :delete
      has_one :profile, {"users_profiles", Profile}
      belongs_to :summary, {"post_summary", Summary}
    end
  end

  test "associations" do
    assert AssocSchema.__schema__(:association, :not_a_field) == nil
    assert AssocSchema.__schema__(:fields) == [:id, :comment_id, :summary_id]
  end

  test "has_many association" do
    struct =
      %Ecto.Association.Has{field: :posts, owner: AssocSchema, cardinality: :many, on_delete: :nothing,
                            related: Post, owner_key: :id, related_key: :assoc_schema_id, queryable: Post,
                            on_replace: :raise}

    assert AssocSchema.__schema__(:association, :posts) == struct
    assert AssocSchema.__changeset__.posts == {:assoc, struct}

    posts = (%AssocSchema{}).posts
    assert %Ecto.Association.NotLoaded{} = posts
    assert inspect(posts) == "#Ecto.Association.NotLoaded<association :posts is not loaded>"
  end

  test "has_many association via {source schema}" do
    struct =
      %Ecto.Association.Has{field: :emails, owner: AssocSchema, cardinality: :many, on_delete: :nothing,
                            related: Email, owner_key: :id, related_key: :assoc_schema_id,
                            queryable: {"users_emails", Email}, on_replace: :delete}

    assert AssocSchema.__schema__(:association, :emails) == struct
    assert AssocSchema.__changeset__.emails == {:assoc, struct}

    posts = (%AssocSchema{}).posts
    assert %Ecto.Association.NotLoaded{__cardinality__: :many} = posts
    assert inspect(posts) == "#Ecto.Association.NotLoaded<association :posts is not loaded>"
  end

  test "has_many association via query" do
    struct = %Ecto.Association.Has{
      field: :low_scoring_posts,
      owner: AssocSchema,
      cardinality: :many,
      on_delete: :nothing,
      related: Post,
      owner_key: :id,
      related_key: :assoc_schema_id,
      queryable: Post.low_score(),
      on_replace: :raise
    }

    assert AssocSchema.__schema__(:association, :low_scoring_posts) == struct
    assert AssocSchema.__changeset__.low_scoring_posts == {:assoc, struct}

    low_scoring_posts = (%AssocSchema{}).low_scoring_posts
    assert %Ecto.Association.NotLoaded{__cardinality__: :many} = low_scoring_posts
    assert inspect(low_scoring_posts) == "#Ecto.Association.NotLoaded<association :low_scoring_posts is not loaded>"
  end

  test "has_many through association" do
    assert AssocSchema.__schema__(:association, :comment_authors) ==
           %Ecto.Association.HasThrough{field: :comment_authors, owner: AssocSchema, cardinality: :many,
                                         through: [:comment, :authors], owner_key: :comment_id}

    refute Map.has_key?(AssocSchema.__changeset__, :comment_authors)

    authors = (%AssocSchema{}).comment_authors
    assert %Ecto.Association.NotLoaded{} = authors
    assert inspect(authors) == "#Ecto.Association.NotLoaded<association :comment_authors is not loaded>"
  end

  test "has_one association" do
    struct =
      %Ecto.Association.Has{field: :author, owner: AssocSchema, cardinality: :one, on_delete: :nothing,
                            related: User, owner_key: :id, related_key: :assoc_schema_id, queryable: User,
                            on_replace: :raise}

    assert AssocSchema.__schema__(:association, :author) == struct
    assert AssocSchema.__changeset__.author == {:assoc, struct}

    author = (%AssocSchema{}).author
    assert %Ecto.Association.NotLoaded{} = author
    assert inspect(author) == "#Ecto.Association.NotLoaded<association :author is not loaded>"
  end

  test "has_one association via {source, schema}" do
    struct =
      %Ecto.Association.Has{field: :profile, owner: AssocSchema, cardinality: :one, on_delete: :nothing,
                            related: Profile, owner_key: :id, related_key: :assoc_schema_id,
                            queryable: {"users_profiles", Profile}, on_replace: :raise}

    assert AssocSchema.__schema__(:association, :profile) == struct
    assert AssocSchema.__changeset__.profile == {:assoc, struct}

    author = (%AssocSchema{}).author
    assert %Ecto.Association.NotLoaded{__cardinality__: :one} = author
    assert inspect(author) == "#Ecto.Association.NotLoaded<association :author is not loaded>"
  end

  test "has_one association via query" do
    struct =
      %Ecto.Association.Has{field: :middle_range_author, owner: AssocSchema, cardinality: :one, on_delete: :nothing,
                            related: User, owner_key: :id, related_key: :assoc_schema_id,
                            queryable: User.middle_range_score(), on_replace: :raise}

    assert AssocSchema.__schema__(:association, :middle_range_author) == struct
    assert AssocSchema.__changeset__.middle_range_author == {:assoc, struct}

    author = (%AssocSchema{}).middle_range_author
    assert %Ecto.Association.NotLoaded{__cardinality__: :one} = author
    assert inspect(author) == "#Ecto.Association.NotLoaded<association :middle_range_author is not loaded>"
  end

  test "has_one through association" do
    assert AssocSchema.__schema__(:association, :comment_main_author) ==
           %Ecto.Association.HasThrough{field: :comment_main_author, owner: AssocSchema, cardinality: :one,
                                         through: [:comment, :main_author], owner_key: :comment_id}

    refute Map.has_key?(AssocSchema.__changeset__, :comment_main_author)

    author = (%AssocSchema{}).comment_main_author
    assert %Ecto.Association.NotLoaded{} = author
    assert inspect(author) == "#Ecto.Association.NotLoaded<association :comment_main_author is not loaded>"
  end

  test "belongs_to association" do
    struct =
      %Ecto.Association.BelongsTo{field: :comment, owner: AssocSchema, cardinality: :one,
       related: Comment, owner_key: :comment_id, related_key: :id, queryable: Comment,
       on_replace: :raise, defaults: []}

    assert AssocSchema.__schema__(:association, :comment) == struct
    assert AssocSchema.__changeset__.comment == {:assoc, struct}

    comment = (%AssocSchema{}).comment
    assert %Ecto.Association.NotLoaded{} = comment
    assert inspect(comment) == "#Ecto.Association.NotLoaded<association :comment is not loaded>"
  end

  test "belongs_to association via {source, schema}" do
    struct =
      %Ecto.Association.BelongsTo{field: :summary, owner: AssocSchema, cardinality: :one,
       related: Summary, owner_key: :summary_id, related_key: :id,
       queryable: {"post_summary", Summary}, on_replace: :raise, defaults: []}

    assert AssocSchema.__schema__(:association, :summary) == struct
    assert AssocSchema.__changeset__.summary == {:assoc, struct}

    comment = (%AssocSchema{}).comment
    assert %Ecto.Association.NotLoaded{} = comment
    assert inspect(comment) == "#Ecto.Association.NotLoaded<association :comment is not loaded>"
  end

  test "belongs_to association via query" do
    struct =
      %Ecto.Association.BelongsTo{field: :high_scoring_comment, owner: AssocSchema, cardinality: :one,
       related: Comment, owner_key: :comment_id, related_key: :id,
       queryable: Comment.high_score(), on_replace: :raise, defaults: []}

    assert AssocSchema.__schema__(:association, :high_scoring_comment) == struct
    assert AssocSchema.__changeset__.high_scoring_comment == {:assoc, struct}

    comment = (%AssocSchema{}).high_scoring_comment
    assert %Ecto.Association.NotLoaded{} = comment
    assert inspect(comment) == "#Ecto.Association.NotLoaded<association :high_scoring_comment is not loaded>"
  end

  test "many_to_many association via query" do
    struct = %Ecto.Association.ManyToMany{
      field: :awesome_editors,
      owner: AssocSchema,
      cardinality: :many,
      on_delete: :nothing,
      related: User,
      owner_key: :id,
      queryable: User.awesome(),
      on_replace: :delete,
      join_keys: [assoc_schema_id: :id, user_id: :id],
      join_through: AssocEditors.active()
    }

    assert AssocSchema.__schema__(:association, :awesome_editors) == struct
    assert AssocSchema.__changeset__.awesome_editors == {:assoc, struct}

    awesome_editors = (%AssocSchema{}).awesome_editors
    assert %Ecto.Association.NotLoaded{__cardinality__: :many} = awesome_editors
    assert inspect(awesome_editors) == "#Ecto.Association.NotLoaded<association :awesome_editors is not loaded>"
  end

  defmodule CustomAssocSchema do
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
    refl = CustomAssocSchema.__schema__(:association, :posts)
    assert :pk == refl.owner_key
    assert :fk == refl.related_key
  end

  test "has_one options" do
    refl = CustomAssocSchema.__schema__(:association, :author)
    assert :pk == refl.owner_key
    assert :fk == refl.related_key
  end

  test "belongs_to options" do
    refl = CustomAssocSchema.__schema__(:association, :permalink1)
    assert :fk == refl.owner_key
    assert :pk == refl.related_key

    refl = CustomAssocSchema.__schema__(:association, :permalink2)
    assert :permalink2_id == refl.owner_key
    assert :pk == refl.related_key

    assert CustomAssocSchema.__schema__(:type, :fk) == :string
    assert CustomAssocSchema.__schema__(:type, :permalink2_id) == :string
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
      defmodule PkAssocMisMatch do
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
      defmodule PkAssocMisMatch do
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
      defmodule ThroughMatch do
        use Ecto.Schema

        schema "assoc" do
          has_many :posts, Post, through: [:whatever, :works]
        end
      end
    end
  end

  test "belongs_to raises helpful error with redundant foreign key name" do
    name = :author
    message = ~r"foreign_key :#{name} must be distinct from corresponding association name"
    assert_raise ArgumentError, message, fn ->
      defmodule SchemaBadForeignKey do
        use Ecto.Schema

        schema "fk_assoc_name_clash" do
          belongs_to name, User, foreign_key: name
        end
      end
    end
  end
end
