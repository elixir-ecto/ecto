Code.require_file "../../integration_test/support/types.exs", __DIR__

defmodule Ecto.SchemaTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use Ecto.Schema

    schema "my schema" do
      field :name,  :string, default: "eric", autogenerate: {String, :upcase, ["eric"]}
      field :email, :string, read_after_writes: true
      field :password, :string, redact: true
      field :temp,  :any, default: "temp", virtual: true, redact: true
      field :count, :decimal, read_after_writes: true, source: :cnt
      field :array, {:array, :string}
      field :uuid, Ecto.UUID, autogenerate: true
      field :query_excluded_field, :string, load_in_query: false
      belongs_to :comment, Comment
      belongs_to :permalink, Permalink, define_field: false
    end
  end

  test "schema metadata" do
    assert Schema.__schema__(:source)             == "my schema"
    assert Schema.__schema__(:prefix)             == nil
    assert Schema.__schema__(:fields)             == [:id, :name, :email, :password, :count, :array, :uuid, :query_excluded_field, :comment_id]
    assert Schema.__schema__(:query_fields)       == [:id, :name, :email, :password, :count, :array, :uuid, :comment_id]
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
    assert Schema.__changeset__() |> Map.drop([:comment, :permalink]) ==
           %{name: :string, email: :string, password: :string, count: :decimal, array: {:array, :string},
             comment_id: :id, temp: :any, id: :id, uuid: Ecto.UUID, query_excluded_field: :string}
  end

  test "autogenerate metadata (private)" do
    assert Schema.__schema__(:autogenerate) ==
           [{[:name], {String, :upcase, ["eric"]}}, {[:uuid], {Ecto.UUID, :autogenerate, []}}]
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
    assert schema.__meta__.source == "my schema"
    assert schema.__meta__.prefix == nil
    schema = Ecto.put_meta(schema, source: "new schema")
    assert schema.__meta__.source == "new schema"
    schema = Ecto.put_meta(schema, prefix: "prefix")
    assert schema.__meta__.prefix == "prefix"
    assert Ecto.get_meta(schema, :prefix) == "prefix"
    assert Ecto.get_meta(schema, :source) == "new schema"
    assert schema.__meta__.schema == Schema

    schema = Ecto.put_meta(schema, context: "foobar", state: :loaded)
    assert schema.__meta__.state == :loaded
    assert schema.__meta__.context == "foobar"
    assert Ecto.get_meta(schema, :state) == :loaded
    assert Ecto.get_meta(schema, :context) == "foobar"
  end

  test "raises on invalid state in metadata" do
    assert_raise ArgumentError, "invalid state nil", fn ->
      Ecto.put_meta(%Schema{}, state: nil)
    end
  end

  test "raises on unknown meta key in metadata" do
    assert_raise ArgumentError, "unknown meta key :foo", fn ->
      Ecto.put_meta(%Schema{}, foo: :bar)
    end
  end

  test "preserves schema on up to date metadata" do
    old_schema = %Schema{}
    new_schema = Ecto.put_meta(old_schema, source: "my schema", state: :built, prefix: nil)
    assert :erts_debug.same(old_schema, new_schema)
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

  test "redacted_fields" do
    assert Schema.__schema__(:redact_fields) == [:temp, :password]
  end

  test "derives inspect" do
    refute inspect(%Schema{password: "hunter2"}) =~ "hunter2"
    refute inspect(%Schema{temp: "hunter2"}) =~ "hunter2"
  end

  defmodule SchemaWithoutDeriveInspect do
    use Ecto.Schema

    @ecto_derive_inspect_for_redacted_fields false

    schema "my_schema" do
      field :password, :string, redact: true
    end
  end

  test "doesn't derive inspect" do
    assert inspect(%SchemaWithoutDeriveInspect{password: "hunter2"}) =~ "hunter2"
  end

  defmodule CustomSchema do
    use Ecto.Schema

    @primary_key {:perm, CustomPermalink, autogenerate: true}
    @foreign_key_type :string
    @field_source_mapper &(&1 |> Atom.to_string |> String.upcase |> String.to_atom())

    schema "users" do
      field :name
      belongs_to :comment, Comment
      field :same_name, :string, source: :NAME
      timestamps()
    end
  end

  test "custom schema attributes" do
    assert %CustomSchema{perm: "abc"}.perm == "abc"
    assert CustomSchema.__schema__(:autogenerate_id) == {:perm, :PERM, CustomPermalink}
    assert CustomSchema.__schema__(:type, :comment_id) == :string
  end

  test "custom primary key" do
    assert Ecto.primary_key(%CustomSchema{}) == [perm: nil]
    assert Ecto.primary_key(%CustomSchema{perm: "hello"}) == [perm: "hello"]
  end

  test "custom field source mapper" do
    assert CustomSchema.__schema__(:field_source, :perm) == :PERM
    assert CustomSchema.__schema__(:field_source, :name) == :NAME
    assert CustomSchema.__schema__(:field_source, :same_name) == :NAME
    assert CustomSchema.__schema__(:field_source, :comment_id) == :COMMENT_ID
    assert CustomSchema.__schema__(:field_source, :inserted_at) == :INSERTED_AT
    assert CustomSchema.__schema__(:field_source, :updated_at) == :UPDATED_AT
  end

  defmodule EmbeddedSchema do
    use Ecto.Schema

    embedded_schema do
      field :name,  :string, default: "eric"
      field :password, :string, redact: true
    end
  end

  test "embedded schema" do
    assert EmbeddedSchema.__schema__(:source)          == nil
    assert EmbeddedSchema.__schema__(:prefix)          == nil
    assert EmbeddedSchema.__schema__(:fields)          == [:id, :name, :password]
    assert EmbeddedSchema.__schema__(:primary_key)     == [:id]
    assert EmbeddedSchema.__schema__(:autogenerate_id) == {:id, :id, :binary_id}
  end

  test "embedded schema does not have metadata" do
    refute match?(%{__meta__: _}, %EmbeddedSchema{})
  end

  test "embedded redacted_fields" do
    assert EmbeddedSchema.__schema__(:redact_fields) == [:password]
  end

  test "embedded derives inspect" do
    refute inspect(%EmbeddedSchema{password: "hunter2"}) =~ "hunter2"
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

  defmodule TimestampsAutoGen do
    use Ecto.Schema

    schema "timestamps_autogen" do
      timestamps autogenerate: {:m, :f, [:a]}
    end
  end

  test "timestamps autogenerate metadata (private)" do
    assert TimestampsAutoGen.__schema__(:autogenerate) ==
           [{[:inserted_at, :updated_at], {:m, :f, [:a]}}]
    assert TimestampsAutoGen.__schema__(:autoupdate) ==
           [{[:updated_at], {:m, :f, [:a]}}]
  end

  defmodule TimestampsCustom do
    use Ecto.Schema

    schema "timestamps" do
      timestamps(
        type: :naive_datetime_usec,
        inserted_at: :created_at,
        inserted_at_source: :createddate,
        updated_at: :modified_at,
        updated_at_source: :modifieddate
      )
    end
  end

  test "timestamps with alternate sources" do
    assert TimestampsCustom.__schema__(:field_source, :created_at) == :createddate
    assert TimestampsCustom.__schema__(:field_source, :modified_at) == :modifieddate
  end

  defmodule TimestampsFalse do
    use Ecto.Schema

    schema "timestamps" do
      timestamps(
        inserted_at: false,
        updated_at: false
      )
    end
  end

  test "timestamps set to false" do
    assert TimestampsFalse.__schema__(:fields) == [:id]
    assert TimestampsFalse.__schema__(:autogenerate) == []
    assert TimestampsFalse.__schema__(:autoupdate) == []
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
    assert %SchemaWithPrefix{}.__meta__.source == "company"
    assert %SchemaWithPrefix{}.__meta__.prefix == "tenant"
  end

  test "schema prefix in queries from" do
    import Ecto.Query

    query = from(SchemaWithPrefix, select: 1)
    assert query.from.prefix == "tenant"

    query = from({"another_company", SchemaWithPrefix}, select: 1)
    assert query.from.prefix == "tenant"

    from = SchemaWithPrefix
    query = from(from, select: 1)
    assert query.from.prefix == "tenant"

    from = {"another_company", SchemaWithPrefix}
    query = from(from, select: 1)
    assert query.from.prefix == "tenant"
  end

  ## Schema context
  defmodule SchemaWithContext do
    use Ecto.Schema

    @schema_context %{some: :data}
    schema "company" do
      field(:name)
    end
  end

  test "schema context metadata" do
    assert %SchemaWithContext{}.__meta__.context == %{some: :data}
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
    assert_raise ArgumentError, ~r"field/association :name already exists on schema", fn ->
      defmodule SchemaFieldNameClash do
        use Ecto.Schema

        schema "clash" do
          field :name, :string
          field :name, :integer
        end
      end
    end
  end

  test "default of invalid type" do
    assert_raise ArgumentError, ~s/value "1" is invalid for type :integer, can't set default/, fn ->
      defmodule SchemaInvalidDefault do
        use Ecto.Schema

        schema "invalid_default" do
          field :count, :integer, default: "1"
        end
      end
    end

    assert_raise ArgumentError, ~s/value 1 is invalid for type :string, can't set default/, fn ->
      defmodule SchemaInvalidDefault do
        use Ecto.Schema

        schema "invalid_default" do
          field :count, :string, default: 1
        end
      end
    end
  end

  test "skipping validations on invalid types" do 
    defmodule SchemaSkipValidationsDefault do
      use Ecto.Schema

      schema "invalid_default" do
        # Without skip_default_validation this would fail to compile
        field :count, :integer, default: "1", skip_default_validation: true
      end
    end
  end

  test "invalid option for field" do
    assert_raise ArgumentError, ~s/invalid option :starts_on for field\/3/, fn ->
      defmodule SchemaInvalidFieldOption do
        use Ecto.Schema

        schema "invalid_option" do
          field :count, :integer, starts_on: 3
        end
      end
    end

    # doesn't validate for parameterized types
    defmodule SchemaInvalidOptionParameterized do
      use Ecto.Schema

      schema "invalid_option_parameterized" do
        field :my_enum, Ecto.Enum, values: [:a, :b], random_option: 3
        field :my_enums, Ecto.Enum, values: [:a, :b], random_option: 3
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

    assert_raise ArgumentError, "unknown type OMG for field :name", fn ->
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

    assert_raise ArgumentError, "unknown type :jsonb for field :name", fn ->
      defmodule SchemaInvalidFieldType do
        use Ecto.Schema

        schema "invalidtype" do
          field :name, :jsonb
        end
      end
    end

    assert_raise ArgumentError, "unknown type :jsonb for field :name", fn ->
      defmodule SchemaInvalidFieldType do
        use Ecto.Schema

        schema "invalidtype" do
          field :name, {:array, :jsonb}
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

  defmodule SchemaWithParameterizedPrimaryKey do
    use Ecto.Schema

    @primary_key {:id, ParameterizedPrefixedString, prefix: "ref", autogenerate: false}
    schema "references" do
    end
  end

  defmodule AssocSchema do
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
      belongs_to :reference, SchemaWithParameterizedPrimaryKey, type: ParameterizedPrefixedString, prefix: "ref"
    end
  end

  test "associations" do
    assert AssocSchema.__schema__(:association, :not_a_field) == nil
    assert AssocSchema.__schema__(:fields) == [:id, :comment_id, :summary_id, :reference_id]
  end

  test "has_many association" do
    struct =
      %Ecto.Association.Has{field: :posts, owner: AssocSchema, cardinality: :many, on_delete: :nothing,
                            related: Post, owner_key: :id, related_key: :assoc_schema_id, queryable: Post,
                            on_replace: :raise}

    assert AssocSchema.__schema__(:association, :posts) == struct
    assert AssocSchema.__changeset__().posts == {:assoc, struct}

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
    assert AssocSchema.__changeset__().emails == {:assoc, struct}

    posts = (%AssocSchema{}).posts
    assert %Ecto.Association.NotLoaded{__cardinality__: :many} = posts
    assert inspect(posts) == "#Ecto.Association.NotLoaded<association :posts is not loaded>"
  end

  test "has_many through association" do
    assert AssocSchema.__schema__(:association, :comment_authors) ==
           %Ecto.Association.HasThrough{field: :comment_authors, owner: AssocSchema, cardinality: :many,
                                         through: [:comment, :authors], owner_key: :comment_id}

    refute Map.has_key?(AssocSchema.__changeset__(), :comment_authors)

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
    assert AssocSchema.__changeset__().author == {:assoc, struct}

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
    assert AssocSchema.__changeset__().profile == {:assoc, struct}

    author = (%AssocSchema{}).author
    assert %Ecto.Association.NotLoaded{__cardinality__: :one} = author
    assert inspect(author) == "#Ecto.Association.NotLoaded<association :author is not loaded>"
  end

  test "has_one through association" do
    assert AssocSchema.__schema__(:association, :comment_main_author) ==
           %Ecto.Association.HasThrough{field: :comment_main_author, owner: AssocSchema, cardinality: :one,
                                         through: [:comment, :main_author], owner_key: :comment_id}

    refute Map.has_key?(AssocSchema.__changeset__(), :comment_main_author)

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
    assert AssocSchema.__changeset__().comment == {:assoc, struct}

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
    assert AssocSchema.__changeset__().summary == {:assoc, struct}

    comment = (%AssocSchema{}).comment
    assert %Ecto.Association.NotLoaded{} = comment
    assert inspect(comment) == "#Ecto.Association.NotLoaded<association :comment is not loaded>"
  end

  test "belongs_to association via Ecto.ParameterizedType" do
    struct =
      %Ecto.Association.BelongsTo{field: :reference, owner: AssocSchema, cardinality: :one,
       related: SchemaWithParameterizedPrimaryKey, owner_key: :reference_id, related_key: :id, queryable: SchemaWithParameterizedPrimaryKey,
       on_replace: :raise, defaults: []}

    assert AssocSchema.__schema__(:association, :reference) == struct
    assert AssocSchema.__changeset__().reference == {:assoc, struct}

    reference = (%AssocSchema{}).reference
    assert %Ecto.Association.NotLoaded{} = reference
    assert inspect(reference) == "#Ecto.Association.NotLoaded<association :reference is not loaded>"
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

  test "has_* validates :on_delete option value" do
    msg =
      "invalid :on_delete option for :posts. The only valid options are: " <>
        "`:nothing`, `:nilify_all`, `:delete_all`"

    assert_raise ArgumentError, msg, fn ->
      defmodule InvalidHasOption do
        use Ecto.Schema

        schema "assoc" do
          has_many :posts, Post, on_delete: nil
        end
      end
    end

    msg =
      "invalid :on_delete option for :post. The only valid options are: " <>
        "`:nothing`, `:nilify_all`, `:delete_all`"

    assert_raise ArgumentError, msg, fn ->
      defmodule InvalidHasOption do
        use Ecto.Schema

        schema "assoc" do
          has_one :post, Post, on_delete: nil
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
    message = ~r"association :posts queryable must be a schema or a {source, schema}. got: 123"
    assert_raise ArgumentError, message, fn ->
      defmodule QueryableMisMatch do
        use Ecto.Schema

        schema "assoc" do
          has_many :posts, 123
        end
      end
    end
  end

  test "has_* through validates option" do
    assert_raise ArgumentError, "invalid option :unknown for has_many/3", fn ->
      defmodule InvalidHasOption do
        use Ecto.Schema

        schema "assoc" do
          has_many :posts, through: [:another], unknown: :option
        end
      end
    end

    assert_raise ArgumentError, "invalid option :unknown for has_one/3", fn ->
      defmodule InvalidHasOption do
        use Ecto.Schema

        schema "assoc" do
          has_one :post, through: [:another], unknown: :option
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

  test "defining schema twice will result with meaningful error" do
    quoted = """
    defmodule DoubleSchema do
      use Ecto.Schema

      schema "my schema" do
        field :name, :string
      end

      schema "my schema" do
        field :name, :string
      end
    end
    """
    message = "schema already defined for DoubleSchema on line 4"

    assert_raise RuntimeError, message, fn ->
      Code.compile_string(quoted, "example.ex")
    end
  end

  describe "type :any" do
    test "raises on non-virtual" do
      assert_raise ArgumentError, ~r"only virtual fields can have type :any", fn ->
        defmodule FieldAny do
          use Ecto.Schema

          schema "anything" do
            field :json, :any
          end
        end
      end
    end

    defmodule FieldAnyVirtual do
      use Ecto.Schema

      schema "anything" do
        field :json, :any, virtual: true
      end
    end

    test "is allowed if virtual" do
      assert %{json: :any} = FieldAnyVirtual.__changeset__()
    end

    defmodule FieldAnyNested do
      use Ecto.Schema

      schema "anything" do
        field :json, {:array, :any}
      end
    end

    test "is allowed if nested" do
      assert %{json: {:array, :any}} = FieldAnyNested.__changeset__()
    end
  end

  describe "preload_order option" do
    test "invalid option" do
      message = "expected `:preload_order` for :posts to be a keyword list or a list of atoms/fields, got: `:title`"
      assert_raise ArgumentError, message, fn ->
        defmodule ThroughMatch do
          use Ecto.Schema

          schema "assoc" do
            has_many :posts, Post, preload_order: :title
          end
        end
      end
    end

    test "invalid direction" do
      message = "expected `:preload_order` for :posts to be a keyword list or a list of atoms/fields, " <>
                  "got: `[invalid_direction: :title]`, `:invalid_direction` is not a valid direction"
      assert_raise ArgumentError, message, fn ->
        defmodule ThroughMatch do
          use Ecto.Schema

          schema "assoc" do
            has_many :posts, Post, preload_order: [invalid_direction: :title]
          end
        end
      end
    end

    test "invalid item" do
      message = "expected `:preload_order` for :posts to be a keyword list or a list of atoms/fields, " <>
                  "got: `[\"text\"]`, `\"text\"` is not valid"
      assert_raise ArgumentError, message, fn ->
        defmodule ThroughMatch do
          use Ecto.Schema

          schema "assoc" do
            has_many :posts, Post, preload_order: ["text"]
          end
        end
      end
    end
  end

  test "raises on :source field not using atom key" do
    assert_raise ArgumentError, ~s(the :source for field `name` must be an atom, got: "string"), fn ->
      defmodule InvalidCustomSchema do
        use Ecto.Schema

        schema "users" do
          field :name, :string, source: "string"
        end
      end
    end
  end
end
