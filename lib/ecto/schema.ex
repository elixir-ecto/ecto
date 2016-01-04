defmodule Ecto.Schema do
  @moduledoc ~S"""
  Defines a schema.

  A schema is a struct with associated metadata that is persisted to a
  repository. Every schema defines a struct, which is ultimately how
  data is manipulated.

  ## Example

      defmodule User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
          field :age, :integer, default: 0
          has_many :posts, Post
        end
      end

  By default, a schema will generate a primary key named `id`
  of type `:integer` and `belongs_to` associations in the schema will generate
  foreign keys of type `:integer`. Those setting can be configured
  below.

  ## Schema attributes

  The schema supports some attributes to be set before hand,
  configuring the defined schema.

  Those attributes are:

    * `@primary_key` - configures the schema primary key. It expects
      a tuple with the primary key name, type (:id or :binary_id) and
      options. Defaults to `{:id, :id, autogenerate: true}`. When set to
      false, does not define a primary key in the schema;

    * `@schema_prefix` - configures the schema prefix. Defaults `nil`
      generate structs and queries without prefix. When set, the
      prefix will be used by every built struct as well as queries
      where the `from` is the current schema;

    * `@foreign_key_type` - configures the default foreign key type
      used by `belongs_to` associations. Defaults to `:integer`;

    * `@timestamps_opts` - configures the default timestamps type
      used by `timestamps`. Defaults to `[type: Ecto.DateTime, usec: false]`;

    * `@derive` - the same as `@derive` available in `Kernel.defstruct/1`
      as the schema defines a struct behind the scenes;

  The advantage of configuring the schema via those attributes is
  that they can be set with a macro to configure application wide
  defaults.

  For example, if your database does not support autoincrementing
  primary keys and requires something like UUID or a RecordID, you
  configure and use`:binary_id` as your primary key type as follows:

      # Define a module to be used as base
      defmodule MyApp.Schema do
        defmacro __using__(_) do
          quote do
            use Ecto.Schema
            @primary_key {:id, :binary_id, autogenerate: true}
            @foreign_key_type :binary_id
          end
        end
      end

      # Now use MyApp.Schema to define new schemas
      defmodule MyApp.Comment do
        use MyApp.Schema

        schema "comments" do
          belongs_to :post, MyApp.Post
        end
      end

  Any schemas using `MyApp.Schema` will get the `:id` field with type
  `:binary_id` as primary key. We explain what the `:binary_id` type
  entails in the next section.

  The `belongs_to` association on `MyApp.Comment` will also define
  a `:post_id` field with `:binary_id` type that references the `:id`
  field of the `MyApp.Post` schema.

  ## Primary keys

  Ecto supports two ID types, called `:id` and `:binary_id`, which are
  often used as the type for primary keys and associations.

  The `:id` type is used when the primary key is an integer while the
  `:binary_id` is used for primary keys in particular binary formats,
  which may be `Ecto.UUID` for databases like PostgreSQL and MySQL,
  or some specific ObjectID or RecordID often imposed by NoSQL databases.

  In both cases, both types have their semantics specified by the
  underlying adapter/database. If you use the `:id` type with
  `:autogenerate`, it means the database will be responsible for
  auto-generation of the id. This is often the case for primary keys
  in relation databases which are auto-incremented.

  Similarly, the `:binary_id` type may be generated in the adapter
  for cases like UUID but it may also be handled by the database if
  required. In any case, both scenarios are handled transparently by
  Ecto.

  Besides `:id` and `:binary_id`, which are often used by primary
  and foreign keys, Ecto provides a huge variety of types to be used
  by any column.

  ## Types and casting

  When defining the schema, types need to be given. Types are split
  in two categories, primitive types and custom types.

  ### Primitive types

  The primitive types are:

  Ecto type               | Elixir type             | Literal syntax in query
  :---------------------- | :---------------------- | :---------------------
  `:id`                   | `integer`               | 1, 2, 3
  `:binary_id`            | `binary`                | `<<int, int, int, ...>>`
  `:integer`              | `integer`               | 1, 2, 3
  `:float`                | `float`                 | 1.0, 2.0, 3.0
  `:boolean`              | `boolean`               | true, false
  `:string`               | UTF-8 encoded `string`  | "hello"
  `:binary`               | `binary`                | `<<int, int, int, ...>>`
  `{:array, inner_type}`  | `list`                  | `[value, value, value, ...]`
  `:decimal`              | [`Decimal`](https://github.com/ericmj/decimal) |
  `:map`                  | `map` |

  **Note:** For the `:array` type, replace `inner_type` with one of
  the valid types, such as `:string`.

  ### Custom types

  Besides providing primitive types, Ecto allows custom types to be
  implemented by developers, allowing Ecto behaviour to be extended.

  A custom type is a module that implements the `Ecto.Type` behaviour.
  By default, Ecto provides the following custom types:

  Custom type             | Database type           | Elixir type
  :---------------------- | :---------------------- | :---------------------
  `Ecto.DateTime`         | `:datetime`             | `%Ecto.DateTime{}`
  `Ecto.Date`             | `:date`                 | `%Ecto.Date{}`
  `Ecto.Time`             | `:time`                 | `%Ecto.Time{}`
  `Ecto.UUID`             | `:uuid`                 | "uuid-string"

  Read the `Ecto.Type` documentation for more information on implementing
  your own types.

  ### The map type

  The map type allows developers to store an Elixir map directly
  in the database:

      # In your migration
      create table(:users) do
        add :data, :map
      end

      # In your schema
      field :data, :map

      # Now in your code
      %User{data: %{"foo" => "bar"}} |> Repo.insert!
      %User{data: %{"foo" => value}} = Repo.one(User)
      value #=> "bar"

  Keep in mind that we advise the map keys to be strings or integers
  instead of atoms. Atoms may be accepted depending on how maps are
  serialized but the database will always return atom keys as strings
  due to security reasons.

  In order to support maps, different databases may employ different
  techniques. For example, PostgreSQL will store those values in jsonb
  fields, allowing you to even query parts of it. MySQL and MSSQL, on
  the other hand, do not yet provide a JSON type, so the value will be
  stored in a text field.

  For maps to work in such databases, Ecto will need a JSON library.
  By default Ecto will use [Poison](http://github.com/devinus/poison)
  which needs to be added your deps in `mix.exs`:

      {:poison, "~> 1.0"}

  You can however tell Ecto to use any other library by configuring it:

      config :ecto, :json_library, YourLibraryOfChoice

  ### Casting

  When directly manipulating the struct, it is the responsibility of
  the developer to ensure the field values have the proper type. For
  example, you can create a user struct with an invalid value
  for `age`:

      iex> user = %User{age: "0"}
      iex> user.age
      "0"

  However, if you attempt to persist the struct above, an error will
  be raised since Ecto validates the types when sending them to the
  adapter/database.

  Therefore, when working and manipulating external data, it is
  recommended the usage of `Ecto.Changeset`'s that are able to filter
  and properly cast external data:

      changeset = Ecto.Changeset.cast(%User{}, %{"age" => "0"}, [:age], [])
      user = Repo.insert!(changeset)

  In fact, `Ecto.Changeset` and custom types provide a powerful
  combination to extend Ecto types and queries.

  Finally, schemas can also have virtual fields by passing the
  `virtual: true` option. These fields are not persisted to the database
  and can optionally not be type checked by declaring type `:any`.

  ## Reflection

  Any schema module will generate the `__schema__` function that can be
  used for runtime introspection of the schema:

  * `__schema__(:source)` - Returns the source as given to `schema/2`;
  * `__schema__(:prefix)` - Returns optional prefix for source provided by
    `@schema_prefix` schema attribute;
  * `__schema__(:primary_key)` - Returns a list of primary key fields (empty if there is none);

  * `__schema__(:fields)` - Returns a list of all non-virtual field names;
  * `__schema__(:type, field)` - Returns the type of the given non-virtual field;
  * `__schema__(:types)` - Returns a keyword list of all non-virtual
    field names and their type;

  * `__schema__(:associations)` - Returns a list of all association field names;
  * `__schema__(:association, assoc)` - Returns the association reflection of the given assoc;

  * `__schema__(:embeds)` - Returns a list of all embedded field names;
  * `__schema__(:embed, embed)` - Returns the embedding reflection of the given embed;

  * `__schema__(:read_after_writes)` - Non-virtual fields that must be read back
    from the database after every write (insert or update);

  * `__schema__(:autogenerate_id)` - Primary key that is auto generated on insert;

  Furthermore, both `__struct__` and `__changeset__` functions are
  defined so structs and changeset functionalities are available.
  """

  @type t :: %{__struct__: atom}

  defmodule Metadata do
    @moduledoc """
    Stores metadata of a struct.

    The fields are:

      * `state` - the state in a struct's lifetime, one of `:built`,
        `:loaded`, `:deleted`
      * `source` - the source for the schema alongside the query prefix,
        defaults to `{nil, "source"}`
      * `context` - context stored by the database

    """
    defstruct [:state, :source, :context]

    defimpl Inspect do
      import Inspect.Algebra

      def inspect(metadata, opts) do
        concat ["#Ecto.Schema.Metadata<", to_doc(metadata.state, opts), ">"]
      end
    end
  end

  @doc false
  defmacro __using__(_) do
    quote do
      import Ecto.Schema, only: [schema: 2, embedded_schema: 1]

      @primary_key {:id, :id, autogenerate: true}
      @timestamps_opts []
      @foreign_key_type :id
      @before_compile Ecto.Schema
      @ecto_embedded false
      @schema_prefix nil

      Module.register_attribute(__MODULE__, :ecto_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_assocs, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_embeds, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_raw, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_autogenerate_insert, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_autogenerate_update, accumulate: true)
      Module.put_attribute(__MODULE__, :ecto_autogenerate_id, nil)
    end
  end

  @doc """
  Defines an embedded schema.

  This function is literally a shortcut for:

        @primary_key {:id, :binary_id, autogenerate: true}
        schema "embedded Model" do
  """
  defmacro embedded_schema(opts) do
    quote do
      @primary_key {:id, :binary_id, autogenerate: true}
      @ecto_embedded true
      schema "embedded #{inspect __MODULE__}", unquote(opts)
    end
  end

  @doc """
  Defines a schema with a source name and field definitions.
  """
  defmacro schema(source, [do: block]) do
    quote do
      prefix = Module.get_attribute(__MODULE__, :schema_prefix)
      source = unquote(source)

      unless is_binary(source) do
        raise ArgumentError, "schema source must be a string, got: #{inspect source}"
      end

      Module.register_attribute(__MODULE__, :changeset_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :struct_fields, accumulate: true)
      Module.put_attribute(__MODULE__, :struct_fields,
                           {:__meta__, %Metadata{state: :built, source: {prefix, source}}})

      primary_key_fields =
        case @primary_key do
          false ->
            []
          {name, type, opts} ->
            Ecto.Schema.__field__(__MODULE__, name, type, true, opts)
            [name]
          other ->
            raise ArgumentError, "@primary_key must be false or {name, type, opts}"
        end

      try do
        import Ecto.Schema
        unquote(block)
      after
        :ok
      end

      fields = @ecto_fields |> Enum.reverse
      assocs = @ecto_assocs |> Enum.reverse
      embeds = @ecto_embeds |> Enum.reverse

      Module.eval_quoted __ENV__, [
        Ecto.Schema.__defstruct__(@struct_fields),
        Ecto.Schema.__changeset__(@changeset_fields),
        Ecto.Schema.__schema__(prefix, source, fields, primary_key_fields),
        Ecto.Schema.__types__(fields),
        Ecto.Schema.__assocs__(assocs),
        Ecto.Schema.__embeds__(embeds),
        Ecto.Schema.__read_after_writes__(@ecto_raw),
        Ecto.Schema.__autogenerate__(@ecto_autogenerate_id,
                                     @ecto_autogenerate_insert,
                                     @ecto_autogenerate_update)]
    end
  end

  ## API

  @doc """
  Defines a field on the schema with given name and type.

  ## Options

    * `:default` - Sets the default value on the schema and the struct.
      The default value is calculated at compilation time, so don't use
      expressions like `Ecto.DateTime.utc` or `Ecto.UUID.generate` as
      they would then be the same for all records

    * `:autogenerate` - Annotates the field to be autogenerated before
      insertion if not value is set.

    * `:read_after_writes` - When true, the field is always read back
      from the database after insert and updates.

      For relational databases, this means the RETURNING option of those
      statements are used. For this reason, MySQL does not support this
      option and will raise an error if a schema is inserted/updated with
      read after writes fields.

    * `:virtual` - When true, the field is not persisted to the database.
      Notice virtual fields do not support `:autogenerate` nor
      `:read_after_writes`.

  """
  defmacro field(name, type \\ :string, opts \\ []) do
    quote do
      Ecto.Schema.__field__(__MODULE__, unquote(name), unquote(type), false, unquote(opts))
    end
  end

  @doc """
  Generates `:inserted_at` and `:updated_at` timestamp fields.

  The fields generated by this macro will automatically be set to
  the current time when inserting and updating values in a repository.

  ## Options

    * `:type` - the timestamps type, defaults to `Ecto.DateTime`.
    * `:usec` - boolean, sets whether microseconds are used in timestamps.
      Microseconds will be 0 if false. Defaults to false.
    * `:inserted_at` - the name of the column for insertion times or `false`
    * `:updated_at` - the name of the column for update times or `false`

  All options can be pre-configured by setting `@timestamps_opts`.
  """
  defmacro timestamps(opts \\ []) do
    quote bind_quoted: binding do
      timestamps =
        [inserted_at: :inserted_at, updated_at: :updated_at,
         type: Ecto.DateTime, usec: false]
        |> Keyword.merge(@timestamps_opts)
        |> Keyword.merge(opts)

      type = Keyword.fetch!(timestamps, :type)
      autogen = if Keyword.fetch!(timestamps, :usec), do: [:usec], else: []

      if inserted_at = Keyword.fetch!(timestamps, :inserted_at) do
        Ecto.Schema.field(inserted_at, type, [])
        Module.put_attribute(__MODULE__, :ecto_autogenerate_insert, {inserted_at, Ecto.DateTime, autogen})
      end

      if updated_at = Keyword.fetch!(timestamps, :updated_at) do
        Ecto.Schema.field(updated_at, type, [])
        Module.put_attribute(__MODULE__, :ecto_autogenerate_insert, {updated_at, Ecto.DateTime, autogen})
        Module.put_attribute(__MODULE__, :ecto_autogenerate_update, {updated_at, Ecto.DateTime, autogen})
      end
    end
  end

  @doc ~S"""
  Indicates a one-to-many association with another schema.

  The current schema has zero or more records of the other schema. The other
  schema often has a `belongs_to` field with the reverse association.

  ## Options

    * `:foreign_key` - Sets the foreign key, this should map to a field on the
      other schema, defaults to the underscored name of the current schema
      suffixed by `_id`

    * `:references` - Sets the key on the current schema to be used for the
      association, defaults to the primary key on the schema

    * `:through` - If this association must be defined in terms of existing
      associations. Read below for more information

    * `:on_delete` - The action taken on associations when parent record
      is deleted. May be `:nothing` (default), `:nilify_all` and `:delete_all`.
      Notice `:on_delete` may also be set in migrations when creating a
      reference. If supported, relying on the database via migrations
      is prefered

    * `:on_replace` - The action taken on associations when the record is
      replaced   when casting or manipulating parent changeset. May be
      `:raise` (default), `:mark_as_invalid`, `:nilify`, or `:delete`.
      See `Ecto.Changeset`'s section on related data for more info.

    * `:defaults` - Default values to use when building the association

  ## Examples

      defmodule Post do
        use Ecto.Schema
        schema "posts" do
          has_many :comments, Comment
        end
      end

      # Get all comments for a given post
      post = Repo.get(Post, 42)
      comments = Repo.all assoc(post, :comments)

      # The comments can come preloaded on the post struct
      [post] = Repo.all(from(p in Post, where: p.id == 42, preload: :comments))
      post.comments #=> [%Comment{...}, ...]

  ## has_many/has_one :through

  Ecto also supports defining associations in terms of other associations
  via the `:through` option. Let's see an example:

      defmodule Post do
        use Ecto.Schema

        schema "posts" do
          has_many :comments, Comment
          has_one :permalink, Permalink

          # In the has_many :through example below, the `:comments`
          # in the list [:comments, :author] refers to the
          # `has_many :comments` in the Post own schema and the
          # `:author` refers to the `belongs_to :author` of the
          # Comment's schema (the module below).
          # (see the description below for more details)
          has_many :comments_authors, through: [:comments, :author]

          # Specify the association with custom source
          has_many :tags, {"posts_tags", Tag}
        end
      end

      defmodule Comment do
        use Ecto.Schema

        schema "comments" do
          belongs_to :author, Author
          belongs_to :post, Post
          has_one :post_permalink, through: [:post, :permalink]
        end
      end

  In the example above, we have defined a `has_many :through` association
  named `:comments_authors`. A `:through` association always expect a list
  and the first element of the list must be a previously defined association
  in the current module. For example, `:comments_authors` first points to
  `:comments` in the same module (Post), which then points to `:author` in
  the next schema `Comment`.

  This `:through` associations will return all authors for all comments
  that belongs to that post:

      # Get all comments for a given post
      post = Repo.get(Post, 42)
      authors = Repo.all assoc(post, :comments_authors)

  `:through` associations are read-only as they are useful to avoid repetition
  allowing the developer to easily retrieve data that is often seem together
  but stored across different tables.

  `:through` associations can also be preloaded. In such cases, not only
  the `:through` association is preloaded but all intermediate steps are
  preloaded too:

      [post] = Repo.all(from(p in Post, where: p.id == 42, preload: :comments_authors))
      post.comments_authors #=> [%Author{...}, ...]

      # The comments for each post will be preloaded too
      post.comments #=> [%Comment{...}, ...]

      # And the author for each comment too
      hd(post.comments).author #=> %Author{...}

  Finally, `:through` can be used with multiple associations (not only 2)
  and with associations of any kind, including `belongs_to` and others
  `:through` associations. When the `:through` association is expected to
  return one or no item, `has_one :through` should be used instead, as in
  the example at the beginning of this section:

      # How we defined the association above
      has_one :post_permalink, through: [:post, :permalink]

      # Get a preloaded comment
      [comment] = Repo.all(Comment) |> Repo.preload(:post_permalink)
      comment.post_permalink #=> %Permalink{...}

  """
  defmacro has_many(name, queryable, opts \\ []) do
    quote do
      Ecto.Schema.__has_many__(__MODULE__, unquote(name), unquote(queryable), unquote(opts))
    end
  end

  @doc ~S"""
  Indicates a one-to-one association with another schema.

  The current schema has zero or one records of the other schema. The other
  schema often has a `belongs_to` field with the reverse association.

  ## Options

    * `:foreign_key` - Sets the foreign key, this should map to a field on the
      other schema, defaults to the underscored name of the current schema
      suffixed by `_id`

    * `:references`  - Sets the key on the current schema to be used for the
      association, defaults to the primary key on the schema

    * `:through` - If this association must be defined in terms of existing
      associations. Read the section in `has_many/3` for more information

    * `:on_delete` - The action taken on associations when parent record
      is deleted. May be `:nothing` (default), `:nilify_all` and `:delete_all`.
      Notice `:on_delete` may also be set in migrations when creating a
      reference. If supported, relying on the database via migrations
      is prefered

    * `:on_replace` - The action taken on associations when the record is
      replaced when casting or manipulating parent changeset. May be
      `:raise` (default), `:mark_as_invalid`, `:nilify`, or `:delete`.
      See `Ecto.Changeset`'s section on related data for more info.

    * `:defaults` - Default values to use when building the association

  ## Examples

      defmodule Post do
        use Ecto.Schema

        schema "posts" do
          has_one :permalink, Permalink

          # Specify the association with custom source
          has_one :category, {"posts_categories", Category}
        end
      end

      # The permalink can come preloaded on the post struct
      [post] = Repo.all(from(p in Post, where: p.id == 42, preload: :permalink))
      post.permalink #=> %Permalink{...}

  """
  defmacro has_one(name, queryable, opts \\ []) do
    quote do
      Ecto.Schema.__has_one__(__MODULE__, unquote(name), unquote(queryable), unquote(opts))
    end
  end

  @doc ~S"""
  Indicates a one-to-one association with another schema.

  The current schema belongs to zero or one records of the other schema. The other
  schema often has a `has_one` or a `has_many` field with the reverse association.

  You should use `belongs_to` in the table that contains the foreign key. Imagine
  a company <-> manager relationship. If the company contains the `manager_id` in
  the underlying database table, we say the company belongs to manager.

  In fact, when you invoke this macro, a field with the name of foreign key is
  automatically defined in the schema for you.

  ## Options

    * `:foreign_key` - Sets the foreign key field name, defaults to the name
      of the association suffixed by `_id`. For example, `belongs_to :company`
      will define foreign key of `:company_id`

    * `:references` - Sets the key on the other schema to be used for the
      association, defaults to: `:id`

    * `:define_field` - When false, does not automatically define a `:foreign_key`
      field, implying the user is defining the field manually elsewhere

    * `:type` - Sets the type of automatically defined `:foreign_key`.
      Defaults to: `:integer` and be set per schema via `@foreign_key_type`

    * `:on_replace` - The action taken on associations when the record is
      replaced   when casting or manipulating parent changeset. May be
      `:raise` (default), `:mark_as_invalid`, `:nilify`, or `:delete`.
      See `Ecto.Changeset`'s section on related data for more info.

    * `:defaults` - Default values to use when building the association

  All other options are forwarded to the underlying foreign key definition
  and therefore accept the same options as `field/3`.

  ## Examples

      defmodule Comment do
        use Ecto.Schema

        schema "comments" do
          belongs_to :post, Post
        end
      end

      # The post can come preloaded on the comment record
      [comment] = Repo.all(from(c in Comment, where: c.id == 42, preload: :post))
      comment.post #=> %Post{...}

  ## Polymorphic associations

  One common use case for belongs to associations is to handle
  polymorphism. For example, imagine you have defined a Comment
  schema and you wish to use it for commenting on both tasks and
  posts.

  Some abstractions would force you to define some sort of
  polymorphic association with two fields in your database:

      * commentable_type
      * commentable_id

  The problem with this approach is that it breaks references in
  the database. You can't use foreign keys and it is very inneficient
  both in terms of query time and storage.

  In Ecto, we have two ways to solve this issue. The simplest one
  is to define multiple fields in the Comment schema, one for each
  association:

      * task_id
      * post_id

  Unless you have dozens of columns, this is simpler for the developer,
  more DB friendly and more efficient on all aspects.

  Alternatively, because Ecto does not tie a schema to a given table,
  we can use separate tables for each association. Let's start over
  and define a new Comment schema:

      defmodule Comment do
        use Ecto.Schema

        schema "abstract table: comments" do
          # This will be used by associations on each "concrete" table
          field :assoc_id, :integer
        end
      end

  Notice we have changed the table name to "abstract table: comments".
  You can choose whatever name you want, the point here is that this
  particular table will never exist.

  Now in your Post and Task schemas:

      defmodule Post do
        use Ecto.Schema

        schema "posts" do
          has_many :comments, {"posts_comments", Comment}, foreign_key: :assoc_id
        end
      end

      defmodule Task do
        use Ecto.Schema

        schema "tasks" do
          has_many :comments, {"tasks_comments", Comment}, foreign_key: :assoc_id
        end
      end

  Now each association uses its own specific table, "posts_comments"
  and "tasks_comments", which must be created on migrations. The
  advantage of this approach is that we never store unrelated data
  together, also ensuring we keep databases references fast and correct.

  When using this technique, the only limitation is that you cannot
  build comments directly. For example, the command below

      Repo.insert!(%Comment{})

  will attempt to use the abstract table. Instead, one should

      Repo.insert!(build_assoc(post, :comments))

  where `build_assoc/3` is defined in `Ecto`. You can also
  use `assoc/2` in both `Ecto` and in the query syntax
  to easily retrieve associated comments to a given post or
  task:

      # Fetch all comments associated to the given task
      Repo.all(assoc(task, :comments))

  Finally, if for some reason you wish to query one of comments
  table directly, you can also specify the tuple source in
  the query syntax:

      Repo.all from(c in {"posts_comments", Comment}), ...)

  """
  defmacro belongs_to(name, queryable, opts \\ []) do
    quote do
      Ecto.Schema.__belongs_to__(__MODULE__, unquote(name), unquote(queryable), unquote(opts))
    end
  end

  @doc ~S"""
  Indicates a many-to-many association with another schema.

  The association happens through a join schema or source, containing
  foreign keys to the associated schemas. For example, the association
  below:

      # from MyApp.Post
      many_to_many :tags, MyApp.Tag, join_through: "posts_tags"

  is backed by relational databases through a join table as follows:

      [Post] <-> [posts_tags] <-> [Tag]
        id   <--   post_id
                    tag_id    -->  id

  More information on the migration for creating such schema is shown
  below.

  ## Options

    * `:join_through` - specifies the source of the associated data.
      It may be a string, like "posts_tags", representing the
      underlying storage table or an atom, like `MyApp.PostTag`,
      representing a schema. This option is required.

    * `:join_keys` - specifies how the schemas are associated. It
      expects a keyword list with two entries, the first being how
      the join table should reach the current schema and the second
      how the join table should reach the associated schema. In the
      example above, it defaults to: `[post_id: :id, tag_id: :id]`.
      The keys are inflected from the schema names.

    * `:on_delete` - The action taken on associations when the parent record
      is deleted. May be `:nothing` (default) or `:delete_all`.
      `:delete_all` will only remove data from the join source, never the
      associated records. Notice `:on_delete` may also be set in migrations
      when creating a reference. If supported, relying on the database via
      migrations is prefered

    * `:on_replace` - The action taken on associations when the record is
      replaced   when casting or manipulating parent changeset. May be
      `:raise` (default), `:mark_as_invalid`, or `:delete`.
      `:delete` will only remove data from the join source, never the
      associated records. See `Ecto.Changeset`'s section on related data
      for more info.

    * `:defaults` - Default values to use when building the association

  ## Removing data

  If you attempt to remove associated `many_to_many` data, be it by
  setting `:on_replace` to `:delete`, `:on_delete` to `:delete_all`
  or by using `Ecto.Changeset.put_assoc/3` and `Ecto.Changeset.cast_assoc/3`,
  **Ecto will always remove data from the join schema and never from
  the target associations**. For example, if a `Post` has a many to many
  relationship with `Tag`, setting a `:on_delete` to `:delete_all` will
  only delete entries from the "posts_tags" table in case `Post` is
  deleted.

  ## Migration

  How your migration should be structured depends on the value you pass
  in `:join_through`. If `:join_through` is simply a string, representing
  a table, you may define a table without primary keys and you must not
  include any further columns, as those values won't be set by Ecto:

      create table(:posts_tags, primary_key: false) do
        add :post_id, references(:posts)
        add :tag_id, references(:tag)
      end

  However, if your `:join_through` is a schema, like `MyApp.PostTag`, your
  join table may be structured as any other table in your codebase,
  including timestamps:

      create table(:posts_tags) do
        add :post_id, references(:posts)
        add :tag_id, references(:tag)
        timestamps
      end

  Because `:join_through` contains a schema, in such cases, autogenerated
  values and primary keys will be automatically handled by Ecto.

  ## Examples

      defmodule Post do
        use Ecto.Schema
        schema "posts" do
          many_to_many :tags, Tag, join_through: "posts_tags"
        end
      end

      # Get all comments for a given post
      post = Repo.get(Post, 42)
      tags = Repo.all assoc(post, :tags)

      # The comments can come preloaded on the post struct
      [post] = Repo.all(from(p in Post, where: p.id == 42, preload: :tags))
      post.tags #=> [%Tag{...}, ...]

  """
  defmacro many_to_many(name, queryable, opts \\ []) do
    quote do
      Ecto.Schema.__many_to_many__(__MODULE__, unquote(name), unquote(queryable), unquote(opts))
    end
  end

  ## Embeds

  @doc ~S"""
  Indicates an embedding of a schema.

  The current schema has zero or one records of the other schema embedded
  inside of it. It uses a field similar to the `:map` type for storage,
  but allows embeds to have all the things regular schema can.

  You must declare your `embeds_one/3` field with type `:map` at the
  database level.

  ## Options

    * `:on_replace` - The action taken on associations when the embed is
      replaced when casting or manipulating parent changeset. May be
      `:raise` (default), `:mark_as_invalid`, or `:delete`.
      See `Ecto.Changeset`'s section on related data for more info.

  ## Examples

      defmodule Order do
        use Ecto.Schema

        schema "orders" do
          embeds_one :item, Item
        end
      end

      defmodule Item do
        use Ecto.Schema

        # A required field for all embedded documents
        @primary_key {:id, :binary_id, autogenerate: true}
        schema "" do
          field :name
        end
      end

      # The item is loaded with the order
      order = Repo.get!(Order, 42)
      order.item #=> %Item{...}

  Adding and removal of embeds can only be done via the `Ecto.Changeset`
  API so Ecto can properly track the embed life-cycle:

      order = Repo.get!(Order, 42)

      # Generate a changeset
      changeset = Ecto.Changeset.change(order)

      # Change, put a new one or remove an item
      changeset = Ecto.Changeset.put_change(order, :item, nil)

      # Update the order
      changeset = Repo.update!(changeset)
  """
  defmacro embeds_one(name, schema, opts \\ []) do
    quote do
      Ecto.Schema.__embeds_one__(__MODULE__, unquote(name), unquote(schema), unquote(opts))
    end
  end

  @doc ~S"""
  Indicates an embedding of many schemas.

  The current schema has zero or more records of the other schema embedded
  inside of it. Embeds have all the things regular schema can.

  It is recommended to declare your `embeds_many/3` field with type
  `{:array, :map}` and default value of `[]` at the database level.
  In fact, Ecto will automatically translate `nil` values from the
  database into empty lists for embeds many (this behaviour is specific
  to `embeds_many/3` fields in order to mimic `has_many/3`).

  ## Options

    * `:on_replace` - The action taken on associations when the embed is
      replaced when casting or manipulating parent changeset. May be
      `:raise` (default), `:mark_as_invalid`, or `:delete`.
      See `Ecto.Changeset`'s section on related data for more info.

  ## Examples

      defmodule Order do
        use Ecto.Schema

        schema "orders" do
          embeds_many :items, Item
        end
      end

      defmodule Item do
        use Ecto.Schema

        # embedded_schema is a shorcut for:
        #
        #   @primary_key {:id, :binary_id, autogenerate: true}
        #   schema "embedded Item" do
        #
        embedded_schema do
          field :name
        end
      end

      # The items are loaded with the order
      order = Repo.get!(Order, 42)
      order.items #=> [%Item{...}, ...]

  Adding and removal of embeds can only be done via the `Ecto.Changeset`
  API so Ecto can properly track the embed life-cycle:

      order = Repo.get!(Order, 42)

      # Generate a changeset
      changeset = Ecto.Changeset.change(order)

      # Change, put a new one or remove all items
      changeset = Ecto.Changeset.put_change(order, :items, [])

      # Update the order
      changeset = Repo.update!(changeset)

  """
  defmacro embeds_many(name, schema, opts \\ []) do
    quote do
      Ecto.Schema.__embeds_many__(__MODULE__, unquote(name), unquote(schema), unquote(opts))
    end
  end

  ## Callbacks

  @doc false
  def __load__(schema, prefix, source, context, data, loader) do
    source = source || schema.__schema__(:source)
    struct = schema.__struct__()
    fields = schema.__schema__(:types)

    struct
    |> do_load(fields, data, loader)
    |> Map.put(:__meta__, %Metadata{state: :loaded, source: {prefix, source}, context: context})
  end

  defp do_load(struct, fields, map, loader) when is_map(map) do
    Enum.reduce(fields, struct, fn
      {field, type}, acc ->
        case Map.fetch(map, Atom.to_string(field)) do
          {:ok, value} -> Map.put(acc, field, load!(type, value, loader))
          :error -> acc
        end
    end)
  end

  defp do_load(struct, types, {fields, values}, loader) when is_list(fields) and is_list(values) do
    do_load(fields, values, struct, types, loader)
  end

  defp do_load([field|fields], [value|values], struct, types, loader) do
    case :lists.keyfind(field, 1, types) do
      {^field, type} ->
        value = load!(type, value, loader)
        do_load(fields, values, Map.put(struct, field, value), types, loader)
      false ->
        raise ArgumentError, "unknown field `#{field}` for struct #{inspect struct.__struct__}"
    end
  end

  defp do_load([], [], struct, _types, _loader), do: struct

  defp load!(type, value, loader) do
    case loader.(type, value) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "cannot load `#{inspect value}` as type #{inspect type}"
    end
  end

  @doc false
  def __field__(mod, name, type, pk?, opts) do
    check_type!(name, type, opts[:virtual])

    default = default_for_type(type, opts)
    check_default!(name, type, default)

    Module.put_attribute(mod, :changeset_fields, {name, type})
    put_struct_field(mod, name, default)

    unless opts[:virtual] do
      if raw = opts[:read_after_writes] do
        Module.put_attribute(mod, :ecto_raw, name)
      end

      if gen = opts[:autogenerate] do
        store_autogenerate!(mod, name, type, pk?)
      end

      if raw && gen do
        raise ArgumentError, "cannot mark the same field as autogenerate and read_after_writes"
      end

      Module.put_attribute(mod, :ecto_fields, {name, type})
    end
  end

  @valid_has_options [:foreign_key, :references, :through, :on_delete, :defaults, :on_replace]

  @doc false
  def __has_many__(mod, name, queryable, opts) do
    check_options!(opts, @valid_has_options, "has_many/3")

    if is_list(queryable) and Keyword.has_key?(queryable, :through) do
      association(mod, :many, name, Ecto.Association.HasThrough, queryable)
    else
      struct =
        association(mod, :many, name, Ecto.Association.Has, [queryable: queryable] ++ opts)
      Module.put_attribute(mod, :changeset_fields, {name, {:assoc, struct}})
    end
  end

  @doc false
  def __has_one__(mod, name, queryable, opts) do
    check_options!(opts, @valid_has_options, "has_one/3")

    if is_list(queryable) and Keyword.has_key?(queryable, :through) do
      association(mod, :one, name, Ecto.Association.HasThrough, queryable)
    else
      struct =
        association(mod, :one, name, Ecto.Association.Has, [queryable: queryable] ++ opts)
      Module.put_attribute(mod, :changeset_fields, {name, {:assoc, struct}})
    end
  end

  @valid_belongs_to_options [:foreign_key, :references, :define_field, :type, :on_replace, :defaults]

  @doc false
  def __belongs_to__(mod, name, queryable, opts) do
    check_options!(opts, @valid_belongs_to_options, "belongs_to/3")

    opts = Keyword.put_new(opts, :foreign_key, :"#{name}_id")
    foreign_key_type = opts[:type] || Module.get_attribute(mod, :foreign_key_type)

    if Keyword.get(opts, :define_field, true) do
      __field__(mod, opts[:foreign_key], foreign_key_type, false, opts)
    end

    struct =
      association(mod, :one, name, Ecto.Association.BelongsTo, [queryable: queryable] ++ opts)
    Module.put_attribute(mod, :changeset_fields, {name, {:assoc, struct}})
  end

  @valid_many_to_many_options [:join_through, :join_keys, :on_delete, :defaults, :on_replace]

  @doc false
  def __many_to_many__(mod, name, queryable, opts) do
    check_options!(opts, @valid_many_to_many_options, "many_to_many/3")

    struct =
      association(mod, :many, name, Ecto.Association.ManyToMany, [queryable: queryable] ++ opts)
    Module.put_attribute(mod, :changeset_fields, {name, {:assoc, struct}})
  end

  @doc false
  def __embeds_one__(mod, name, schema, opts) do
    check_options!(opts, [:strategy, :on_replace], "embeds_one/3")
    embed(mod, :one, name, schema, opts)
  end

  @doc false
  def __embeds_many__(mod, name, schema, opts) do
    check_options!(opts, [:strategy, :on_replace], "embeds_many/3")
    opts = Keyword.put(opts, :default, [])
    embed(mod, :many, name, schema, opts)
  end

  ## Quoted callbacks

  @doc false
  def __changeset__(changeset_fields) do
    map = changeset_fields |> Enum.into(%{}) |> Macro.escape()
    quote do
      def __changeset__, do: unquote(map)
    end
  end

  @doc false
  def __defstruct__(struct_fields) do
    quote do
      defstruct unquote(Macro.escape(struct_fields))
    end
  end

  @doc false
  def __schema__(prefix, source, fields, primary_key) do
    field_names = Enum.map(fields, &elem(&1, 0))

    # Hash is used by the query cache to specify
    # the underlying schema structure did not change.
    # We don't include the source because the source
    # is already part of the query cache itself.
    hash = :erlang.phash2({primary_key, fields})

    quote do
      def __schema__(:query),       do: %Ecto.Query{from: {unquote(source), __MODULE__}, prefix: unquote(prefix)}
      def __schema__(:prefix),      do: unquote(prefix)
      def __schema__(:source),      do: unquote(source)
      def __schema__(:fields),      do: unquote(field_names)
      def __schema__(:primary_key), do: unquote(primary_key)
      def __schema__(:hash),        do: unquote(hash)
    end
  end

  @doc false
  def __types__(fields) do
    quoted =
      Enum.map(fields, fn {name, type} ->
        quote do
          def __schema__(:type, unquote(name)) do
            unquote(Macro.escape(type))
          end
        end
      end)

    types = Macro.escape(fields)

    quote do
      def __schema__(:types), do: unquote(types)
      unquote(quoted)
      def __schema__(:type, _), do: nil
    end
  end

  @doc false
  def __assocs__(assocs) do
    quoted =
      Enum.map(assocs, fn {name, refl} ->
        quote do
          def __schema__(:association, unquote(name)) do
            unquote(Macro.escape(refl))
          end
        end
      end)

    assoc_names = Enum.map(assocs, &elem(&1, 0))

    quote do
      def __schema__(:associations), do: unquote(assoc_names)
      unquote(quoted)
      def __schema__(:association, _), do: nil
    end
  end

  @doc false
  def __embeds__(embeds) do
    quoted =
      Enum.map(embeds, fn {name, refl} ->
        quote do
          def __schema__(:embed, unquote(name)) do
            unquote(Macro.escape(refl))
          end
        end
      end)

    embed_names = Enum.map(embeds, &elem(&1, 0))

    quote do
      def __schema__(:embeds), do: unquote(embed_names)
      unquote(quoted)
      def __schema__(:embed, _), do: nil
    end
  end

  @doc false
  def __read_after_writes__(fields) do
    quote do
      def __schema__(:read_after_writes), do: unquote(Enum.reverse(fields))
    end
  end

  @doc false
  def __autogenerate__(id, insert, update) do
    quote do
      def __schema__(:autogenerate_id), do: unquote(id)
      def __schema__(:autogenerate, :insert), do: unquote(Macro.escape(insert))
      def __schema__(:autogenerate, :update), do: unquote(Macro.escape(update))
    end
  end

  @doc false
  def __before_compile__(env) do
    unless Module.get_attribute(env.module, :struct_fields) do
      raise "module #{inspect env.module} uses Ecto.Schema but it " <>
            "does not define a schema. Please cherry pick the functionality you want " <>
            "instead, for example, by importing Ecto.Query, Ecto.Schema or others"
    end
  end

  ## Private

  defp association(mod, cardinality, name, association, opts) do
    if Module.get_attribute(mod, :ecto_embedded) do
      raise "association can't be defined in embedded_schema for #{inspect mod}"
    end

    not_loaded  = %Ecto.Association.NotLoaded{__owner__: mod,
                    __field__: name, __cardinality__: cardinality}
    put_struct_field(mod, name, not_loaded)
    opts = [cardinality: cardinality] ++ opts
    struct = association.struct(mod, name, opts)
    Module.put_attribute(mod, :ecto_assocs, {name, struct})

    struct
  end

  defp embed(mod, cardinality, name, schema, opts) do
    opts   = [cardinality: cardinality, related: schema] ++ opts
    struct = Ecto.Embedded.struct(mod, name, opts)

    __field__(mod, name, {:embed, struct}, false, opts)
    Module.put_attribute(mod, :ecto_embeds, {name, struct})
  end

  defp put_struct_field(mod, name, assoc) do
    fields = Module.get_attribute(mod, :struct_fields)

    if List.keyfind(fields, name, 0) do
      raise ArgumentError, "field/association #{inspect name} is already set on schema"
    end

    Module.put_attribute(mod, :struct_fields, {name, assoc})
  end

  defp check_options!(opts, valid, fun_arity) do
    case Enum.find(opts, fn {k, _} -> not k in valid end) do
      {k, _} ->
        raise ArgumentError, "invalid option #{inspect k} for #{fun_arity}"
      nil ->
        :ok
    end
  end

  defp check_type!(name, type, virtual?) do
    cond do
      type == :any and not virtual? ->
        raise ArgumentError, "only virtual fields can have type :any, " <>
                             "invalid type for field #{inspect name}"
      Ecto.Type.primitive?(type) and not type in [:date, :time, :datetime] ->
        true
      is_atom(type) ->
        if Code.ensure_compiled?(type) and function_exported?(type, :type, 0) do
          type
        else
          raise_type_error(name, type)
        end
      true ->
        raise ArgumentError, "invalid type #{inspect type} for field #{inspect name}"
    end
  end

  defp raise_type_error(name, type) do
    raise ArgumentError, "invalid or unknown type #{inspect type} for field #{inspect name}" <>
                         raise_type_error_hint(type)
  end

  defp raise_type_error_hint(:datetime),
    do: ". Maybe you meant to use Ecto.DateTime?"
  defp raise_type_error_hint(:date),
    do: ". Maybe you meant to use Ecto.Date?"
  defp raise_type_error_hint(:time),
    do: ". Maybe you meant to use Ecto.Time?"
  defp raise_type_error_hint(:uuid),
    do: ". Maybe you meant to use Ecto.UUID?"
  defp raise_type_error_hint(_),
    do: ""

  # Skip embed check because embedded schema may not yet be compiled
  defp check_default!(_name, {:embed, _}, _default), do: :ok
  defp check_default!(name, type, default) do
    case Ecto.Type.dump(type, default) do
      {:ok, _} ->
        :ok
      :error ->
        raise ArgumentError, "invalid default argument `#{inspect default}` for " <>
                             "field #{inspect name} of type #{inspect type}"
    end
  end

  defp store_autogenerate!(mod, name, type, true) do
    if id = autogenerate_id(type) do
      if Module.get_attribute(mod, :ecto_autogenerate_id) do
        raise ArgumentError, "only one primary key with ID type may be marked as autogenerated"
      end

      Module.put_attribute(mod, :ecto_autogenerate_id, {name, id})
    else
      store_autogenerate!(mod, name, type, false)
    end
  end

  defp store_autogenerate!(mod, name, type, false) do
    cond do
      _ = autogenerate_id(type) ->
        raise ArgumentError, "only primary keys allow :autogenerate for type #{inspect type}, " <>
                             "field #{inspect name} is not a primary key"

      Ecto.Type.primitive?(type) ->
        raise ArgumentError, "field #{inspect name} does not support :autogenerate because it uses a " <>
                             "primitive type #{inspect type}"

      # Note the custom type has already been loaded in check_type!/3
      not function_exported?(type, :generate, 0) ->
        raise ArgumentError, "field #{inspect name} does not support :autogenerate because it uses a " <>
                             "custom type #{inspect type} that does not define generate/0"

      true ->
        Module.put_attribute(mod, :ecto_autogenerate_insert, {name, type, []})
    end
  end

  defp autogenerate_id(type) do
    id = if Ecto.Type.primitive?(type), do: type, else: type.type
    if id in [:id, :binary_id], do: id, else: nil
  end

  defp default_for_type(_, opts) do
    Keyword.get(opts, :default)
  end
end
