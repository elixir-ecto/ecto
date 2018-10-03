defmodule Ecto.Schema do
  @moduledoc ~S"""
  Defines a schema.

  An Ecto schema is used to map any data source into an Elixir struct.
  One of such use cases is to map data coming from a repository,
  usually a table, into Elixir structs.

  ## Example

      defmodule User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
          field :age, :integer, default: 0
          has_many :posts, Post
        end
      end

  By default, a schema will automatically generate a primary key which is named
  `id` and of type `:integer`. The `field` macro defines a field in the schema
  with given name and type.  `has_many` associates many posts with the user
  schema.

  ## Schema attributes

  Supported attributes, to be set beforehand, for configuring the defined schema.

  These attributes are:

    * `@primary_key` - configures the schema primary key. It expects
      a tuple `{field_name, type, options}` with the primary key field
      name, type (typically `:id` or `:binary_id`, but can be any type) and
      options. Defaults to `{:id, :id, autogenerate: true}`. When set
      to `false`, does not define a primary key in the schema unless
      composite keys are defined using the options of `field`.

    * `@schema_prefix` - configures the schema prefix. Defaults to `nil`,
      which generates structs and queries without prefix. When set, the
      prefix will be used by every built struct and on queries where the
      current schema is used in `from` (and only `from` exclusively). If
      a schema is used as a join or part of an assoc, `@schema_prefix` won't
      be obeyed. In PostgreSQL, the prefix is called "SCHEMA" (typically
      set via Postgres' `search_path`). In MySQL the prefix points to databases.

    * `@foreign_key_type` - configures the default foreign key type
      used by `belongs_to` associations. Defaults to `:id`;

    * `@timestamps_opts` - configures the default timestamps type
      used by `timestamps`. Defaults to `[type: :naive_datetime, usec: true]`;

    * `@derive` - the same as `@derive` available in `Kernel.defstruct/1`
      as the schema defines a struct behind the scenes;

    * `@field_source_mapper` - a function that receives the current field name
      and returns the mapping of this field name in the underlying source.
      In other words, it is a mechanism to automatically generate the `:source`
      option for the `field` macro. It defaults to `fn x -> x end`, where no
      field transformation is done;

  The advantage of configuring the schema via those attributes is
  that they can be set with a macro to configure application wide
  defaults.

  For example, if your database does not support autoincrementing
  primary keys and requires something like UUID or a RecordID, you
  can configure and use`:binary_id` as your primary key type as follows:

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
  `:binary_id` as the primary key. We explain what the `:binary_id` type
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
  in relational databases which are auto-incremented.

  Similarly, the `:binary_id` type may be generated in the adapter
  for cases like UUID but it may also be handled by the database if
  required. In any case, both scenarios are handled transparently by
  Ecto.

  Besides `:id` and `:binary_id`, which are often used by primary
  and foreign keys, Ecto provides a huge variety of types to be used
  by any column.

  Ecto also supports composite primary keys.

  ## Types and casting

  When defining the schema, types need to be given. Types are split
  into two categories, primitive types and custom types.

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
  `:map`                  | `map` |
  `{:map, inner_type}`    | `map` |
  `:decimal`              | [`Decimal`](https://github.com/ericmj/decimal) |

  **Note:** For the `{:array, inner_type}` and `{:map, inner_type}` type,
  replace `inner_type` with one of the valid types, such as `:string`.

  Since Ecto 2.1, Ecto also supports the Calendar types that are part
  of Elixir standard library:

  Ecto type               | Elixir type
  :---------------------- | :----------------------
  `:date`                 | `Date`
  `:time`                 | `Time`
  `:naive_datetime`       | `NaiveDateTime`
  `:utc_datetime`         | `DateTime`

  Timestamps are typically represented by `:naive_datetime` or
  `:utc_datetime`. The naive datetime uses Elixir's `NaiveDateTime` which
  has no timezone information while `:utc_datetime` uses a `DateTime` and
  expects the time_zone to be set to UTC.

  ### Custom types

  Besides providing primitive types, Ecto allows custom types to be
  implemented by developers, allowing Ecto behaviour to be extended.

  A custom type is a module that implements the `Ecto.Type` behaviour.
  By default, Ecto provides the following custom types:

  Custom type             | Database type           | Elixir type
  :---------------------- | :---------------------- | :---------------------
  `Ecto.UUID`             | `:uuid`                 | `uuid-string`

  Read the `Ecto.Type` documentation for more information on implementing
  your own types.

  Finally, schemas can also have virtual fields by passing the
  `virtual: true` option. These fields are not persisted to the database
  and can optionally not be type checked by declaring type `:any`.

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
      user = Repo.insert! %User{data: %{"foo" => "bar"}}

  Keep in mind that we advise the map keys to be strings or integers
  instead of atoms. Atoms may be accepted depending on how maps are
  serialized but the database will always return atom keys as strings
  due to security reasons.

  In order to support maps, different databases may employ different
  techniques. For example, PostgreSQL will store those values in jsonb
  fields, allowing you to just query parts of it. MySQL and MSSQL, on
  the other hand, do not yet provide a JSON type, so the value will be
  stored in a text field.

  For maps to work in such databases, Ecto will need a JSON library.
  By default Ecto will use [Poison](http://github.com/devinus/poison)
  which needs to be added your deps in `mix.exs`:

      {:poison, "~> 1.0"}

  You can however tell Ecto to use any other library by configuring it:

      config :ecto, :json_library, YourLibraryOfChoice

  If changing the JSON library, remember to recompile Ecto afterwards by
  cleaning the current build:

      mix deps.clean --build ecto

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

  Therefore, when working with and manipulating external data, it is
  recommended to use `Ecto.Changeset`'s that are able to filter
  and properly cast external data:

      changeset = Ecto.Changeset.cast(%User{}, %{"age" => "0"}, [:age])
      user = Repo.insert!(changeset)

  **You can use Ecto schemas and changesets to cast and validate any kind
  of data, regardless if the data will be persisted to an Ecto repository
  or not**.

  ## Reflection

  Any schema module will generate the `__schema__` function that can be
  used for runtime introspection of the schema:

  * `__schema__(:source)` - Returns the source as given to `schema/2`;
  * `__schema__(:prefix)` - Returns optional prefix for source provided by
    `@schema_prefix` schema attribute;
  * `__schema__(:primary_key)` - Returns a list of primary key fields (empty if there is none);

  * `__schema__(:fields)` - Returns a list of all non-virtual field names;
  * `__schema__(:field_source, field)` - Returns the alias of the given field;

  * `__schema__(:type, field)` - Returns the type of the given non-virtual field;

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

  @type t :: struct

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
        %{source: {prefix, source}, state: state, context: context} = metadata
        entries =
          for entry <- [state, prefix, source, context],
              entry != nil,
              do: to_doc(entry, opts)
        concat ["#Ecto.Schema.Metadata<"] ++ Enum.intersperse(entries, ", ") ++ [">"]
      end
    end
  end

  @doc false
  defmacro __using__(_) do
    quote do
      import Ecto.Schema, only: [schema: 2, embedded_schema: 1]

      @primary_key nil
      @timestamps_opts []
      @foreign_key_type :id
      @schema_prefix nil
      @field_source_mapper fn x -> x end

      Module.register_attribute(__MODULE__, :ecto_primary_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_field_sources, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_assocs, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_embeds, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_raw, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_autogenerate, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_autoupdate, accumulate: true)
      Module.put_attribute(__MODULE__, :ecto_autogenerate_id, nil)
    end
  end

  @doc """
  Defines an embedded schema.

  An embedded schema does not require a source name
  and it does not include a metadata field.

  Embedded schemas by default set the primary key type
  to `:binary_id` but such can be configured with the
  `@primary_key` attribute.
  """
  defmacro embedded_schema([do: block]) do
    schema(nil, false, :binary_id, block)
  end

  @doc """
  Defines a schema with a source name and field definitions.
  """
  defmacro schema(source, [do: block]) do
    schema(source, true, :id, block)
  end

  defp schema(source, meta?, type, block) do
    quote do
      @after_compile Ecto.Schema
      Module.register_attribute(__MODULE__, :changeset_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :struct_fields, accumulate: true)

      meta?  = unquote(meta?)
      source = unquote(source)
      prefix = @schema_prefix

      # Those module attributes are accessed only dynamically
      # so we explicitly reference them here to avoid warnings.
      _ = @foreign_key_type
      _ = @timestamps_opts

      if meta? do
        unless is_binary(source) do
          raise ArgumentError, "schema source must be a string, got: #{inspect source}"
        end

        Module.put_attribute(__MODULE__, :struct_fields,
                             {:__meta__, %Metadata{state: :built, source: {prefix, source}}})
      end

      if @primary_key == nil do
        @primary_key {:id, unquote(type), autogenerate: true}
      end

      primary_key_fields =
        case @primary_key do
          false ->
            []
          {name, type, opts} ->
            Ecto.Schema.__field__(__MODULE__, name, type, [primary_key: true] ++ opts)
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

      primary_key_fields = @ecto_primary_keys |> Enum.reverse
      autogenerate = @ecto_autogenerate |> Enum.reverse
      autoupdate = @ecto_autoupdate |> Enum.reverse
      fields = @ecto_fields |> Enum.reverse
      field_sources = @ecto_field_sources |> Enum.reverse
      assocs = @ecto_assocs |> Enum.reverse
      embeds = @ecto_embeds |> Enum.reverse

      Module.eval_quoted __ENV__, [
        Ecto.Schema.__defstruct__(@struct_fields),
        Ecto.Schema.__changeset__(@changeset_fields),
        Ecto.Schema.__schema__(prefix, source, fields, primary_key_fields),
        Ecto.Schema.__types__(fields, field_sources),
        Ecto.Schema.__dumper__(fields, field_sources),
        Ecto.Schema.__loader__(fields, field_sources),
        Ecto.Schema.__field_sources__(fields, field_sources),
        Ecto.Schema.__assocs__(assocs),
        Ecto.Schema.__embeds__(embeds),
        Ecto.Schema.__read_after_writes__(@ecto_raw),
        Ecto.Schema.__autogenerate__(@ecto_autogenerate_id, autogenerate, autoupdate)]
    end
  end

  ## API

  @doc """
  Defines a field on the schema with given name and type.

  ## Options

    * `:default` - Sets the default value on the schema and the struct.
      The default value is calculated at compilation time, so don't use
      expressions like `DateTime.utc_now` or `Ecto.UUID.generate` as
      they would then be the same for all records.

    * `:source` - Defines the name that is to be used in database for this field.

    * `:autogenerate` - Annotates the field to be autogenerated before
      insertion if value is not set. It will call the `autogenerate/0`
      function in the field's type.

    * `:read_after_writes` - When true, the field is always read back
      from the database after insert and updates.

      For relational databases, this means the RETURNING option of those
      statements is used. For this reason, MySQL does not support this
      option and will raise an error if a schema is inserted/updated with
      read after writes fields.

    * `:virtual` - When true, the field is not persisted to the database.
      Notice virtual fields do not support `:autogenerate` nor
      `:read_after_writes`.

    * `:primary_key` - When true, the field is used as part of the
      composite primary key

  """
  defmacro field(name, type \\ :string, opts \\ []) do
    quote do
      Ecto.Schema.__field__(__MODULE__, unquote(name), unquote(type), unquote(opts))
    end
  end

  @doc """
  Generates `:inserted_at` and `:updated_at` timestamp fields.

  The fields generated by this macro will automatically be set to
  the current time when inserting and updating values in a repository.

  ## Options

    * `:type` - the timestamps type, defaults to `:naive_datetime`.
    * `:usec` - sets whether microseconds are used in timestamps.
      Microseconds will be 0 if false. Defaults to true.
    * `:inserted_at` - the name of the column for insertion times or `false`
    * `:updated_at` - the name of the column for update times or `false`
    * `:autogenerate` - a module-function-args tuple used for generating
      both `inserted_at` and `updated_at` timestamps

  All options can be pre-configured by setting `@timestamps_opts`.
  """
  defmacro timestamps(opts \\ []) do
    quote bind_quoted: binding() do
      timestamps =
        [inserted_at: :inserted_at, updated_at: :updated_at,
         type: :naive_datetime, usec: true]
        |> Keyword.merge(@timestamps_opts)
        |> Keyword.merge(opts)

      type      = Keyword.fetch!(timestamps, :type)
      precision = if Keyword.fetch!(timestamps, :usec), do: :microsecond, else: :second
      autogen   = timestamps[:autogenerate] || {Ecto.Schema, :__timestamps__, [type, precision]}

      if inserted_at = Keyword.fetch!(timestamps, :inserted_at) do
        Ecto.Schema.field(inserted_at, type, [])
        Module.put_attribute(__MODULE__, :ecto_autogenerate, {inserted_at, autogen})
      end

      if updated_at = Keyword.fetch!(timestamps, :updated_at) do
        Ecto.Schema.field(updated_at, type, [])
        Module.put_attribute(__MODULE__, :ecto_autogenerate, {updated_at, autogen})
        Module.put_attribute(__MODULE__, :ecto_autoupdate, {updated_at, autogen})
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

    * `:through` - Allow this association to be defined in terms of existing
      associations. Read the section on `:through` associations for more info

    * `:on_delete` - The action taken on associations when parent record
      is deleted. May be `:nothing` (default), `:nilify_all` and `:delete_all`.
      Notice `:on_delete` may also be set in migrations when creating a
      reference. If supported, relying on the database via migrations
      is preferred. `:nilify_all` and `:delete_all` will not cascade to child
      records unless set via database migrations.

    * `:on_replace` - The action taken on associations when the record is
      replaced when casting or manipulating parent changeset. May be
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
  named `:comments_authors`. A `:through` association always expects a list
  and the first element of the list must be a previously defined association
  in the current module. For example, `:comments_authors` first points to
  `:comments` in the same module (Post), which then points to `:author` in
  the next schema, `Comment`.

  This `:through` association will return all authors for all comments
  that belongs to that post:

      # Get all comments for a given post
      post = Repo.get(Post, 42)
      authors = Repo.all assoc(post, :comments_authors)

  Although we used the `:through` association in the example above, Ecto
  also allows developers to dynamically build the through associations using
  the `Ecto.assoc/2` function:

      assoc(post, [:comments, :author])

  In fact, given `:through` associations are read-only, **using the `Ecto.assoc/2`
  format is the preferred mechanism for working with through associations**. Use
  the schema-based one only if you need to store the through data alongside of
  the parent struct, in specific cases such as preloading.

  `:through` associations can also be preloaded. In such cases, not only
  the `:through` association is preloaded but all intermediate steps are
  preloaded too:

      [post] = Repo.all(from(p in Post, where: p.id == 42, preload: :comments_authors))
      post.comments_authors #=> [%Author{...}, ...]

      # The comments for each post will be preloaded too
      post.comments #=> [%Comment{...}, ...]

      # And the author for each comment too
      hd(post.comments).author #=> %Author{...}

  When the `:through` association is expected to return one or zero items,
  `has_one :through` should be used instead, as in the example at the beginning
  of this section:

      # How we defined the association above
      has_one :post_permalink, through: [:post, :permalink]

      # Get a preloaded comment
      [comment] = Repo.all(Comment) |> Repo.preload(:post_permalink)
      comment.post_permalink #=> %Permalink{...}

  """
  defmacro has_many(name, queryable, opts \\ []) do
    queryable = expand_alias(queryable, __CALLER__)
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
      is preferred. `:nilify_all` and `:delete_all` will not cascade to child
      records unless set via database migrations.

    * `:on_replace` - The action taken on associations when the record is
      replaced when casting or manipulating parent changeset. May be
      `:raise` (default), `:mark_as_invalid`, `:nilify`, `:update`, or
      `:delete`. See `Ecto.Changeset`'s section on related data for more info.

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
    queryable = expand_alias(queryable, __CALLER__)
    quote do
      Ecto.Schema.__has_one__(__MODULE__, unquote(name), unquote(queryable), unquote(opts))
    end
  end

  @doc ~S"""
  Indicates a one-to-one or many-to-one association with another schema.

  The current schema belongs to zero or one records of the other schema. The other
  schema often has a `has_one` or a `has_many` field with the reverse association.

  You should use `belongs_to` in the table that contains the foreign key. Imagine
  a company <-> employee relationship. If the employee contains the `company_id` in
  the underlying database table, we say the employee belongs to company.

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
      Defaults to: `:integer` and can be set per schema via `@foreign_key_type`

    * `:on_replace` - The action taken on associations when the record is
      replaced when casting or manipulating parent changeset. May be
      `:raise` (default), `:mark_as_invalid`, `:nilify`, `:update`, or `:delete`.
      See `Ecto.Changeset`'s section on related data for more info.

    * `:defaults` - Default values to use when building the association

    * `:primary_key` - If the underlying belongs_to field is a primary key

    * `:source` - The source for the underlying field

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

  If you need custom options on the underlying field, you can define the
  field explicitly and then pass `define_field: false` to `belongs_to`:

      defmodule Comment do
        use Ecto.Schema

        schema "comments" do
          field :post_id, :integer, ... # custom options
          belongs_to :post, Post, define_field: false
        end
      end

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
  the database. You can't use foreign keys and it is very inefficient,
  both in terms of query time and storage.

  In Ecto, we have three ways to solve this issue. The simplest
  is to define multiple fields in the Comment schema, one for each
  association:

      * task_id
      * post_id

  Unless you have dozens of columns, this is simpler for the developer,
  more DB friendly and more efficient in all aspects.

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
  together, also ensuring we keep database references fast and correct.

  When using this technique, the only limitation is that you cannot
  build comments directly. For example, the command below

      Repo.insert!(%Comment{})

  will attempt to use the abstract table. Instead, one should use

      Repo.insert!(build_assoc(post, :comments))

  where `build_assoc/3` is defined in `Ecto`. You can also
  use `assoc/2` in both `Ecto` and in the query syntax
  to easily retrieve associated comments to a given post or
  task:

      # Fetch all comments associated with the given task
      Repo.all(assoc(task, :comments))

  Or all comments in a given table:

      Repo.all from(c in {"posts_comments", Comment}), ...)

  The third and final option is to use `many_to_many/3` to
  define the relationships between the resources. In this case,
  the comments table won't have the foreign key, instead there
  is a intermediary table responsible for associating the entries:

      defmodule Comment do
        use Ecto.Schema
        schema "comments" do
          # ...
        end
      end

  In your posts and tasks:

      defmodule Post do
        use Ecto.Schema

        schema "posts" do
          many_to_many :comments, Comment, join_through: "posts_comments"
        end
      end

      defmodule Task do
        use Ecto.Schema

        schema "tasks" do
          many_to_many :comments, Comment, join_through: "tasks_comments"
        end
      end

  See `many_to_many/3` for more information on this particular approach.
  """
  defmacro belongs_to(name, queryable, opts \\ []) do
    queryable = expand_alias(queryable, __CALLER__)
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

  More information on the migration for creating such a schema is shown
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
      migrations is preferred. `:nilify_all` and `:delete_all` will not cascade
      to child records unless set via database migrations.

    * `:on_replace` - The action taken on associations when the record is
      replaced when casting or manipulating parent changeset. May be
      `:raise` (default), `:mark_as_invalid`, or `:delete`.
      `:delete` will only remove data from the join source, never the
      associated records. See `Ecto.Changeset`'s section on related data
      for more info.

    * `:defaults` - Default values to use when building the association

    * `:unique` - When true, checks if the associated entries are unique.
      This is done by checking the primary key of the associated entries during
      repository operations. Keep in mind this does not guarantee uniqueness at the
      database level. For such it is preferred to set a unique index in the database.
      For example: `create unique_index(:posts_tags, [:post_id, :tag_id])`

  ## Removing data

  If you attempt to remove associated `many_to_many` data, **Ecto will
  always remove data from the join schema and never from the target
  associations** be it by setting `:on_replace` to `:delete`, `:on_delete`
  to `:delete_all` or by using changeset functions such as
  `Ecto.Changeset.put_assoc/3`. For example, if a `Post` has a many to many
  relationship with `Tag`, setting `:on_delete` to `:delete_all` will
  only delete entries from the "posts_tags" table in case `Post` is
  deleted.

  ## Migration

  How your migration should be structured depends on the value you pass
  in `:join_through`. If `:join_through` is simply a string, representing
  a table, you may define a table without primary keys and you must not
  include any further columns, as those values won't be set by Ecto:

      create table(:posts_tags, primary_key: false) do
        add :post_id, references(:posts)
        add :tag_id, references(:tags)
      end

  However, if your `:join_through` is a schema, like `MyApp.PostTag`, your
  join table may be structured as any other table in your codebase,
  including timestamps:

      create table(:posts_tags) do
        add :post_id, references(:posts)
        add :tag_id, references(:tags)
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

      # Let's create a post and a tag
      post = Repo.insert!(%Post{})
      tag = Repo.insert!(%Tag{name: "introduction"})

      # We can associate at any time post and tags together using changesets
      post
      |> Repo.preload(:tags) # Load existing data
      |> Ecto.Changeset.change() # Build the changeset
      |> Ecto.Changeset.put_assoc(:tags, [tag]) # Set the association
      |> Repo.update!

      # In a later moment, we may get all tags for a given post
      post = Repo.get(Post, 42)
      tags = Repo.all(assoc(post, :tags))

      # The tags may also be preloaded on the post struct for reading
      [post] = Repo.all(from(p in Post, where: p.id == 42, preload: :tags))
      post.tags #=> [%Tag{...}, ...]

  ## Join Schema Example

  You may prefer to use a join schema to handle many_to_many associations. The
  decoupled nature of Ecto allows us to create a "join" struct which
  `belongs_to` both sides of the many to many association.

  In our example, a User has and belongs to many Organizations

      defmodule UserOrganization do
        use Ecto.Schema

        @primary_key false
        schema "users_organizations" do
          belongs_to :user, User
          belongs_to :organization, Organization
          timestamps # Added bonus, a join schema will also allow you to set timestamps
        end

        def changeset(struct, params \\ %{}) do
          struct
          |> Ecto.Changeset.cast(params, [:user_id, :organization_id])
          |> Ecto.Changeset.validate_required([:user_id, :organization_id])
          # Maybe do some counter caching here!
        end
      end

      defmodule User do
        use Ecto.Schema

        schema "users" do
          many_to_many :organizations, Organization, join_through: UserOrganization
        end
      end

      defmodule Organization do
        use Ecto.Schema

        schema "organizations" do
          many_to_many :users, User, join_through: UserOrganization
        end
      end

      # Then to create the association, pass in the ID's of an existing
      # User and Organization to UserOrganization.changeset
      changeset = UserOrganization.changeset(%UserOrganization{}, %{user_id: id, organization_id: id})

      case Repo.insert(changeset) do
        {:ok, assoc} -> # Assoc was created!
        {:error, changeset} -> # Handle the error
      end
  """
  defmacro many_to_many(name, queryable, opts \\ []) do
    queryable = expand_alias(queryable, __CALLER__)
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

  The embedded may or may not have a primary key. Ecto use the primary keys
  to detect if an embed is being updated or not. If a primary is not present,
  `:on_replace` should be set to either `:update` or `:delete` if there is a
  desire to either update or delete the current embed when a new one is set.

  ## Options

    * `:on_replace` - The action taken on associations when the embed is
      replaced when casting or manipulating parent changeset. May be
      `:raise` (default), `:mark_as_invalid`, `:update`, or `:delete`.
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

        embedded_schema do
          field :title
        end
      end

      # The item is loaded with the order
      order = Repo.get!(Order, 42)
      order.item #=> %Item{...}

  Adding and removal of embeds can only be done via the `Ecto.Changeset`
  API so Ecto can properly track the embed life-cycle:

      order = Repo.get!(Order, 42)
      item  = %Item{title: "Soap"}

      # Generate a changeset
      changeset = Ecto.Changeset.change(order)

      # Put a new embed to the changeset
      changeset = Ecto.Changeset.put_embed(changeset, :item, item)

      # Update the order, and fetch the item
      item = Repo.update!(changeset).item

      # Item is generated with a unique identification
      item
      # => %Item{id: "20a97d94-f79b-4e63-a875-85deed7719b7", title: "Soap"}

  ## Inline embedded schema

  The schema module can be defined inline in the parent schema in simple
  cases:

      defmodule Parent do
        use Ecto.Schema

        schema "parents" do
          field :name, :string

          embeds_one :child, Child do
            field :name, :string
            field :age,  :integer
          end
        end
      end

  When defining an inline embed, the `:primary_key` option may be given to
  customize the embed primary key type.

  Defining embedded schema in such a way will define a `Parent.Child` module
  with the appropriate struct. In order to properly cast the embedded schema.
  When casting the inline-defined embedded schemas you need to use the `:with`
  option of `cast_embed/3` to provide the proper function to do the casting.
  For example:

      def changeset(schema, params) do
        schema
        |> cast(params, [:name])
        |> cast_embed(:child, with: &child_changeset/2)
      end

      defp child_changeset(schema, params) do
        schema
        |> cast(params, [:name, :age])
      end

  ## Encoding and decoding

  Because many databases do not support direct encoding and decoding
  of embeds, it is often emulated by Ecto by using specific encoding
  and decoding rules.

  For example, PostgreSQL will store embeds on top of JSONB columns,
  which means types in embedded schemas won't go through the usual
  dump->DB->load cycle but rather encode->DB->decode->cast. This means
  that, when using embedded schemas with databases like PG or MySQL,
  make sure all of your types can be JSON encoded/decoded correctly.
  Ecto provides this guarantee for all built-in types.
  """
  defmacro embeds_one(name, schema, opts \\ [])

  defmacro embeds_one(name, schema, do: block) do
    quote do
      embeds_one(unquote(name), unquote(schema), [], do: unquote(block))
    end
  end

  defmacro embeds_one(name, schema, opts) do
    schema = expand_alias(schema, __CALLER__)
    quote do
      Ecto.Schema.__embeds_one__(__MODULE__, unquote(name), unquote(schema), unquote(opts))
    end
  end

  @doc """
  Indicates an embedding of a schema.

  For options and examples see documentation of `embeds_one/3`.
  """
  defmacro embeds_one(name, schema, opts, do: block) do
    quote do
      {schema, opts} = Ecto.Schema.__embeds_module__(__ENV__, unquote(schema), unquote(opts), unquote(Macro.escape(block)))
      Ecto.Schema.__embeds_one__(__MODULE__, unquote(name), schema, opts)
    end
  end

  @doc ~S"""
  Indicates an embedding of many schemas.

  The current schema has zero or more records of the other schema embedded
  inside of it. Embeds have all the things regular schemas have.

  It is recommended to declare your `embeds_many/3` field with type
  `{:array, :map}` and a default of `[]` at the database level, or type `:jsonb`
  with a default of `"[]"` if you are using PostgreSQL. In fact, Ecto will
  automatically translate `nil` values from the database into empty lists for
  embeds many (this behaviour is specific to `embeds_many/3` fields in order
  to mimic `has_many/3`).

  The embedded may or may not have a primary key. Ecto use the primary keys
  to detect if an embed is being updated or not. If a primary is not present
  and you still want the list of embeds to be updated, `:on_replace` must be
  set to `:delete`, forcing all current embeds to be deleted and replaced by
  new ones whenever a new list of embeds is set.

  For encoding and decoding of embeds, please read the docs for
  `embeds_one/3`.

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

        embedded_schema do
          field :title
        end
      end

      # The items are loaded with the order
      order = Repo.get!(Order, 42)
      order.items #=> [%Item{...}, ...]

  Adding and removal of embeds can only be done via the `Ecto.Changeset`
  API so Ecto can properly track the embed life-cycle:

      # Order has no items
      order = Repo.get!(Order, 42)
      order.items
      # => []

      items  = [%Item{title: "Soap"}]

      # Generate a changeset
      changeset = Ecto.Changeset.change(order)

      # Put a one or more new items
      changeset = Ecto.Changeset.put_embed(changeset, :items, items)

      # Update the order and fetch items
      items = Repo.update!(changeset).items

      # Items are generated with a unique identification
      items
      # => [%Item{id: "20a97d94-f79b-4e63-a875-85deed7719b7", title: "Soap"}]

  Updating of embeds must be done using a changeset for each changed embed.

      # Order has an existing items
      order = Repo.get!(Order, 42)
      order.items
      # => [%Item{id: "20a97d94-f79b-4e63-a875-85deed7719b7", title: "Soap"}]

      # Generate a changeset
      changeset = Ecto.Changeset.change(order)

      # Put the updated item as a changeset
      current_item = List.first(order.items)
      item_changeset = Ecto.Changeset.change(current_item, title: "Mujju's Soap")
      order_changeset = Ecto.Changeset.put_embed(changeset, :items, [item_changeset])

      # Update the order and fetch items
      items = Repo.update!(order_changeset).items

      # Item has the updated title
      items
      # => [%Item{id: "20a97d94-f79b-4e63-a875-85deed7719b7", title: "Mujju's Soap"}]


  ## Inline embedded schema

  The schema module can be defined inline in the parent schema in simple
  cases:

      defmodule Parent do
        use Ecto.Schema

        schema "parents" do
          field :name, :string

          embeds_many :children, Child do
            field :name, :string
            field :age,  :integer
          end
        end
      end

  When defining an inline embed, the `:primary_key` option may be given to
  customize the embed primary key type.

  Defining embedded schema in such a way will define a `Parent.Child` module
  with the appropriate struct. In order to properly cast the embedded schema.
  When casting the inline-defined embedded schemas you need to use the `:with`
  option of `cast_embed/3` to provide the proper function to do the casting.
  For example:

      def changeset(schema, params) do
        schema
        |> cast(params, [:name])
        |> cast_embed(:children, with: &child_changeset/2)
      end

      defp child_changeset(schema, params) do
        schema
        |> cast(params, [:name, :age])
      end

  """
  defmacro embeds_many(name, schema, opts \\ [])

  defmacro embeds_many(name, schema, do: block) do
    quote do
      embeds_many(unquote(name), unquote(schema), [], do: unquote(block))
    end
  end

  defmacro embeds_many(name, schema, opts) do
    schema = expand_alias(schema, __CALLER__)
    quote do
      Ecto.Schema.__embeds_many__(__MODULE__, unquote(name), unquote(schema), unquote(opts))
    end
  end

  @doc """
  Indicates an embedding of many schemas.

  For options and examples see documentation of `embeds_many/3`.
  """
  defmacro embeds_many(name, schema, opts, do: block) do
    quote do
      {schema, opts} = Ecto.Schema.__embeds_module__(__ENV__, unquote(schema), unquote(opts), unquote(Macro.escape(block)))
      Ecto.Schema.__embeds_many__(__MODULE__, unquote(name), schema, opts)
    end
  end

  @doc """
  Internal function for integrating associations into schemas.

  This function exists as an extension point for libraries to
  add new types of associations to Ecto. For the existing APIs,
  see `belongs_to/3`, `has_many/3`, `has_one/3` and `many_to_many/3`.

  This function expects the current schema, the association cardinality,
  the association name, the association module (that implements
  `Ecto.Association` callbacks) and a keyword list of options.
  """
  @spec association(module, :one | :many, atom(), module, Keyword.t) :: Ecto.Association.t
  def association(schema, cardinality, name, association, opts) do
    not_loaded  = %Ecto.Association.NotLoaded{__owner__: schema,
                    __field__: name, __cardinality__: cardinality}
    put_struct_field(schema, name, not_loaded)
    opts = [cardinality: cardinality] ++ opts
    struct = association.struct(schema, name, opts)
    Module.put_attribute(schema, :ecto_assocs, {name, struct})
    struct
  end

  ## Callbacks

  @doc false
  def __timestamps__(:naive_datetime, :second) do
    %{NaiveDateTime.utc_now() | microsecond: {0, 6}}
  end
  def __timestamps__(:naive_datetime, :microsecond) do
    NaiveDateTime.utc_now()
  end
  def __timestamps__(type, :second) do
    type_to_module(type).from_unix!(System.system_time(:second) * 1000000, :microsecond)
  end
  def __timestamps__(type, :microsecond) do
    type_to_module(type).from_unix!(System.system_time(:microsecond), :microsecond)
  end

  defp type_to_module(:naive_datetime), do: NaiveDateTime
  defp type_to_module(:utc_datetime), do: DateTime
  defp type_to_module(other), do: other

  @doc false
  # Loads data into struct by assumes fields are properly
  # named and belongs to the struct. Types and values are
  # zipped together in one pass as they are loaded.
  def __safe_load__(struct, types, values, prefix, source, loader) do
    zipped = safe_load_zip(types, values, struct, loader)

    case Map.merge(struct, Map.new(zipped)) do
      %{__meta__: %Metadata{} = metadata} = struct ->
        metadata = %{metadata | state: :loaded, source: {prefix, source}}
        Map.put(struct, :__meta__, metadata)
      map ->
        map
    end
  end

  defp safe_load_zip([{field, type} | fields], [value | values], struct, loader) do
    [{field, load!(struct, field, type, value, loader)} |
     safe_load_zip(fields, values, struct, loader)]
  end
  defp safe_load_zip([], [], _struct, _loader) do
    []
  end

  @doc false
  # Assumes data does not all belongs to schema/struct
  # and that it may also require source-based renaming.
  def __unsafe_load__(schema, data, loader) do
    types = schema.__schema__(:load)
    struct = schema.__struct__()
    case __unsafe_load__(struct, types, data, loader) do
      %{__meta__: %Metadata{} = metadata} = struct ->
        Map.put(struct, :__meta__, %{metadata | state: :loaded})
      map ->
        map
    end
  end

  @doc false
  def __unsafe_load__(struct, types, map, loader) when is_map(map) do
    Enum.reduce(types, struct, fn pair, acc ->
      {field, source, type} = field_source_and_type(pair)
      case fetch_string_or_atom_field(map, source) do
        {:ok, value} -> Map.put(acc, field, load!(struct, field, type, value, loader))
        :error -> acc
      end
    end)
  end

  @compile {:inline, field_source_and_type: 1, fetch_string_or_atom_field: 2}
  defp field_source_and_type({field, {:source, source, type}}) do
    {field, source, type}
  end
  defp field_source_and_type({field, type}) do
    {field, field, type}
  end

  defp fetch_string_or_atom_field(map, field) when is_atom(field) do
    case Map.fetch(map, Atom.to_string(field)) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(map, field)
    end
  end

  defp load!(struct, field, type, value, loader) do
    case loader.(type, value) do
      {:ok, value} ->
        value
      :error ->
        raise ArgumentError, "cannot load `#{inspect value}` as type #{inspect type} " <>
                             "for field `#{field}`#{error_data(struct)}"
    end
  end

  defp error_data(%{__struct__: atom}) do
    " in schema #{inspect atom}"
  end
  defp error_data(other) when is_map(other) do
    ""
  end

  @doc false
  def __field__(mod, name, type, opts) do
    virtual? = opts[:virtual] || false
    check_type!(name, type, virtual?)
    pk? = opts[:primary_key] || false

    default = default_for_type(type, opts)
    Module.put_attribute(mod, :changeset_fields, {name, type})
    put_struct_field(mod, name, default)

    unless virtual? do
      source = opts[:source] || Module.get_attribute(mod, :field_source_mapper).(name)
      if name != source do
        Module.put_attribute(mod, :ecto_field_sources, {name, source})
      end

      if raw = opts[:read_after_writes] do
        Module.put_attribute(mod, :ecto_raw, name)
      end

      case gen = opts[:autogenerate] do
        {_, _, _} ->
          store_mfa_autogenerate!(mod, name, type, gen)
        true ->
          store_type_autogenerate!(mod, name, source || name, type, pk?)
        _ ->
          :ok
      end

      if raw && gen do
        raise ArgumentError, "cannot mark the same field as autogenerate and read_after_writes"
      end

      if pk? do
        Module.put_attribute(mod, :ecto_primary_keys, name)
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

  # :primary_key is valid here to support associative entity
  # https://en.wikipedia.org/wiki/Associative_entity
  @valid_belongs_to_options [:foreign_key, :references, :define_field, :type,
                             :on_replace, :defaults, :primary_key, :source]

  @doc false
  def __belongs_to__(mod, name, queryable, opts) do
    check_options!(opts, @valid_belongs_to_options, "belongs_to/3")

    opts = Keyword.put_new(opts, :foreign_key, :"#{name}_id")
    foreign_key_type = opts[:type] || Module.get_attribute(mod, :foreign_key_type)

    if name == Keyword.get(opts, :foreign_key) do
      raise ArgumentError, "foreign_key #{inspect name} must be distinct from corresponding association name"
    end

    if Keyword.get(opts, :define_field, true) do
      __field__(mod, opts[:foreign_key], foreign_key_type, opts)
    end

    struct =
      association(mod, :one, name, Ecto.Association.BelongsTo, [queryable: queryable] ++ opts)
    Module.put_attribute(mod, :changeset_fields, {name, {:assoc, struct}})
  end

  @valid_many_to_many_options [:join_through, :join_keys, :on_delete, :defaults, :on_replace, :unique]

  @doc false
  def __many_to_many__(mod, name, queryable, opts) do
    check_options!(opts, @valid_many_to_many_options, "many_to_many/3")

    struct =
      association(mod, :many, name, Ecto.Association.ManyToMany, [queryable: queryable] ++ opts)
    Module.put_attribute(mod, :changeset_fields, {name, {:assoc, struct}})
  end

  @valid_embeds_one_options [:strategy, :on_replace, :source]

  @doc false
  def __embeds_one__(mod, name, schema, opts) do
    check_options!(opts, @valid_embeds_one_options, "embeds_one/3")
    embed(mod, :one, name, schema, opts)
  end

  @valid_embeds_many_options [:strategy, :on_replace, :source]

  @doc false
  def __embeds_many__(mod, name, schema, opts) do
    check_options!(opts, @valid_embeds_many_options, "embeds_many/3")
    opts = Keyword.put(opts, :default, [])
    embed(mod, :many, name, schema, opts)
  end

  @doc false
  def __embeds_module__(env, name, opts, block) do
    {pk, opts} = Keyword.pop(opts, :primary_key, {:id, :binary_id, autogenerate: true})

    block =
      quote do
        use Ecto.Schema

        @primary_key unquote(Macro.escape(pk))
        embedded_schema do
          unquote(block)
        end
      end

    module = Module.concat(env.module, name)
    Module.create(module, block, env)
    {module, opts}
  end

  ## Quoted callbacks

  @doc false
  def __after_compile__(%{module: module} = env, _) do
    # TODO: This is a hack, don't do this at home, it may break any time.
    # We need to provide a proper API for this in Elixir.
    if Process.info(self(), :error_handler) == {:error_handler, Kernel.ErrorHandler} do
      for name <- module.__schema__(:associations) do
        assoc = module.__schema__(:association, name)
        case assoc.__struct__.after_compile_validation(assoc, env) do
          :ok -> :ok
          {:error, message} ->
            IO.warn "invalid association `#{assoc.field}` in schema #{inspect module}: #{message}",
                    Macro.Env.stacktrace(env)
        end
      end
    end
    :ok
  end

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
  def __types__(fields, field_sources) do
    fields_quoted =
      Enum.map(fields, fn {name, type} ->
        quote do
          def __schema__(:type, unquote(name)) do
            unquote(Macro.escape(type))
          end
        end
      end)

    sources_quoted =
      Enum.map(fields, fn {name, type} ->
        quote do
          def __schema__(:source_type, unquote(field_sources[name] || name)) do
            unquote(Macro.escape(type))
          end
        end
      end)

    types = Macro.escape(Map.new(fields))

    quote do
      def __schema__(:types), do: unquote(types)
      unquote(fields_quoted)
      def __schema__(:type, _), do: nil
      unquote(sources_quoted)
      def __schema__(:source_type, _), do: nil
    end
  end

  @doc false
  def __dumper__(fields, field_sources) do
    mapping =
      for {name, type} <- fields do
        {name, {field_sources[name] || name, Macro.escape(type)}}
      end

    quote do
      def __schema__(:dump), do: %{unquote_splicing(mapping)}
    end
  end

  @doc false
  def __loader__(fields, field_sources) do
    mapping =
      for {name, type} <- fields do
        if alias = field_sources[name] do
          {name, Macro.escape({:source, alias, type})}
        else
          {name, Macro.escape(type)}
        end
      end

    quote do
      def __schema__(:load), do: unquote(mapping)
    end
  end

  @doc false
  def __field_sources__(fields, field_sources) do
    quoted =
      Enum.map(fields, fn {name, _type} ->
        quote do
          def __schema__(:field_source, unquote(name)) do
            unquote(field_sources[name] || name)
          end
        end
      end)

    quote do
      unquote(quoted)
      def __schema__(:field_source, _field), do: nil
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
      def __schema__(:autogenerate_id), do: unquote(Macro.escape(id))
      def __schema__(:autogenerate), do: unquote(Macro.escape(insert))
      def __schema__(:autoupdate), do: unquote(Macro.escape(update))
    end
  end

  ## Private

  defp embed(mod, cardinality, name, schema, opts) do
    opts   = [cardinality: cardinality, related: schema] ++ opts
    struct = Ecto.Embedded.struct(mod, name, opts)

    __field__(mod, name, {:embed, struct}, opts)
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
    case Enum.find(opts, fn {k, _} -> not(k in valid) end) do
      {k, _} ->
        raise ArgumentError, "invalid option #{inspect k} for #{fun_arity}"
      nil ->
        :ok
    end
  end

  defp check_type!(name, type, virtual?) do
    cond do
      type == :datetime ->
        raise ArgumentError, "invalid type :datetime for field #{inspect name}. " <>
                             "You probably meant to choose one between :naive_datetime " <>
                             "(no timezone information) or :utc_datetime (timezone is set to UTC)"
      type == :any and not virtual? ->
        raise ArgumentError, "only virtual fields can have type :any, " <>
                             "invalid type for field #{inspect name}"
      type == Ecto.DateTime ->
        IO.warn "Ecto.DateTime is deprecated, plese use :naive_datetime instead"
        type
      type == Ecto.Date ->
        IO.warn "Ecto.Date is deprecated, plese use :date instead"
        type
      type == Ecto.Time ->
        IO.warn "Ecto.Time is deprecated, plese use :time instead"
        type
      Ecto.Type.primitive?(type) ->
        type
      is_atom(type) ->
        if Code.ensure_compiled?(type) and function_exported?(type, :type, 0) do
          type
        else
          raise ArgumentError, "invalid or unknown type #{inspect type} for field #{inspect name}"
        end
      true ->
        raise ArgumentError, "invalid type #{inspect type} for field #{inspect name}"
    end
  end

  defp store_mfa_autogenerate!(mod, name, type, mfa) do
    if autogenerate_id(type) do
      raise ArgumentError, ":autogenerate with {m, f, a} not supported by ID types"
    else
      Module.put_attribute(mod, :ecto_autogenerate, {name, mfa})
    end
  end

  defp store_type_autogenerate!(mod, name, source, type, pk?) do
    cond do
      id = autogenerate_id(type) ->
        cond do
          not pk? ->
            raise ArgumentError, "only primary keys allow :autogenerate for type #{inspect type}, " <>
                                 "field #{inspect name} is not a primary key"
          Module.get_attribute(mod, :ecto_autogenerate_id) ->
            raise ArgumentError, "only one primary key with ID type may be marked as autogenerated"
          true ->
            Module.put_attribute(mod, :ecto_autogenerate_id, {name, source, id})
        end

      Ecto.Type.primitive?(type) ->
        raise ArgumentError, "field #{inspect name} does not support :autogenerate because it uses a " <>
                             "primitive type #{inspect type}"

      # Note the custom type has already been loaded in check_type!/3
      not function_exported?(type, :autogenerate, 0) ->
        raise ArgumentError, "field #{inspect name} does not support :autogenerate because it uses a " <>
                             "custom type #{inspect type} that does not define autogenerate/0"

      true ->
        Module.put_attribute(mod, :ecto_autogenerate, {name, {type, :autogenerate, []}})
    end
  end

  defp autogenerate_id(type) do
    id = if Ecto.Type.primitive?(type), do: type, else: type.type
    if id in [:id, :binary_id], do: id, else: nil
  end

  defp default_for_type(_, opts) do
    Keyword.get(opts, :default)
  end

  defp expand_alias({:__aliases__, _, _} = ast, env),
    do: Macro.expand(ast, %{env | function: {:__schema__, 2}})
  defp expand_alias(ast, _env),
    do: ast
end
