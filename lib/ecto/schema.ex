defmodule Ecto.Schema do
  @moduledoc ~S"""
  Defines a schema for a model.

  A schema is a struct with associated metadata that is persisted to a
  repository. Every schema model is also a struct, that means that you work
  with models just like you would work with structs.

  ## Example

      defmodule User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
          field :age, :integer, default: 0
          has_many :posts, Post
        end
      end

  By default, a schema will generate both a primary key named `id`
  of type `:integer` and `belongs_to` associations will generate
  foreign keys of type `:integer` too. Those setting can be configured
  below.

  ## Schema attributes

  The schema supports some attributes to be set before hand,
  configuring the defined schema.

  Those attributes are:

    * `@primary_key` - configures the schema primary key. It expects
      a tuple with the primary key name, type and options. Defaults
      to `{:id, :integer, read_after_writes: true}`. When set to
      false, does not define a primary key in the model;

    * `@foreign_key_type` - configures the default foreign key type
      used by `belongs_to` associations. Defaults to `:integer`;

    * `@timestamps_opts` - configures the default timestamps type
      used by `timestamps`. Defaults to `[type: Ecto.DateTime, usec: false]`;

    * `@derive` - the same as `@derive` available in `Kernel.defstruct/1`
      as the schema defines a struct behind the scenes;

  The advantage of defining configure the schema via those attributes
  is that they can be set with a macro to configure application wide
  defaults. For example, if you would like to use `uuid`'s in all of
  your application models, you can do:

      # Define a module to be used as base
      defmodule MyApp.Model do
        defmacro __using__(_) do
          quote do
            use Ecto.Model
            @primary_key {:id, :uuid, []}
            @foreign_key_type :uuid
          end
        end
      end

      # Now use MyApp.Model to define new models
      defmodule MyApp.Comment do
        use MyApp.Model

        schema "comments" do
          belongs_to :post, MyApp.Post
        end
      end

  Any models using `MyApp.Model` will get the `:id` field with type
  `:uuid` as primary key.

  The `belongs_to` association on `MyApp.Comment` will also define
  a `:post_id` field with `:uuid` type that references the `:id` of
  the `MyApp.Post` model.

  ## Types and casting

  When defining the schema, types need to be given. Types are split
  in two categories, primitive types and custom types.

  ### Primitive types

  The primitive types are:

  Ecto type               | Elixir type             | Literal syntax in query
  :---------------------- | :---------------------- | :---------------------
  `:integer`              | `integer`               | 1, 2, 3
  `:float`                | `float`                 | 1.0, 2.0, 3.0
  `:boolean`              | `boolean`               | true, false
  `:string`               | UTF-8 encoded `string`  | "hello"
  `:binary`               | `binary`                | `<<int, int, int, ...>>`
  `:uuid`                 | 16 byte `binary`        | `uuid(binary_or_string)`
  `{:array, inner_type}`  | `list`                  | `[value, value, value, ...]`
  `:decimal`              | [`Decimal`](https://github.com/ericmj/decimal)
  `:datetime`             | `{{year, month, day}, {hour, min, sec}}`
  `:date`                 | `{year, month, day}`
  `:time`                 | `{hour, min, sec}`

  **Note:** Although Ecto provides `:date`, `:time` and `:datetime`, you
  likely want to use `Ecto.Date`, `Ecto.Time` and `Ecto.DateTime` respectively.
  See the Custom types sections below about types that enhance the primitive
  ones.

  ### Custom types

  Sometimes the primitive types in Ecto are too primitive. For example,
  `:uuid` relies on the underling binary representation instead of
  representing itself as a readable string. That's where `Ecto.UUID`
  comes in.

  `Ecto.UUID` is a  custom type. A custom type is a module that
  implements the `Ecto.Type` behaviour. By default, Ecto provides the
  following custom types:

  Custom type             | Ecto type               | Elixir type
  :---------------------- | :---------------------- | :---------------------
  `Ecto.DateTime`         | `:datetime`             | `%Ecto.DateTime{}`
  `Ecto.Date`             | `:date`                 | `%Ecto.Date{}`
  `Ecto.Time`             | `:time`                 | `%Ecto.Time{}`
  `Ecto.UUID`             | `:uuid`                 | "uuid-string"

  Ecto allow developers to provide their own types too. Read the
  `Ecto.Type` documentation for more information.

  ### Casting

  When directly manipulating the struct, it is the responsibility of
  the developer to ensure the field values have the proper type. For
  example, you can create a weather struct with an invalid value
  for `temp_lo`:

      iex> weather = %Weather{temp_lo: "0"}
      iex> weather.temp_lo
      "0"

  However, if you attempt to persist the struct above, an error will
  be raised since Ecto validates the types when building the query.

  Therefore, when working and manipulating external data, it is
  recommended the usage of `Ecto.Changeset`'s that are able to filter
  and properly cast external data. In fact, `Ecto.Changeset` and custom
  types provide a powerful combination to extend Ecto types and queries.

  Finally, models can also have virtual fields by passing the
  `virtual: true` option. These fields are not persisted to the database
  and can optionally not be type checked by declaring type `:any`.

  ## Reflection

  Any schema module will generate the `__schema__` function that can be
  used for runtime introspection of the schema:

  * `__schema__(:source)` - Returns the source as given to `schema/2`;
  * `__schema__(:primary_key)` - Returns a list of the field that is the primary
    key or [] if there is none;

  * `__schema__(:fields)` - Returns a list of all non-virtual field names;
  * `__schema__(:field, field)` - Returns the type of the given non-virtual field;

  * `__schema__(:associations)` - Returns a list of all association field names;
  * `__schema__(:association, assoc)` - Returns the association reflection of the given assoc;

  * `__schema__(:read_after_writes)` - Non-virtual fields that must be read back
    from the database after every write (insert or update);

  * `__schema__(:load, source, idx, values)` - Loads a new model from a tuple of non-virtual
    field values starting at the given index. Typically used by adapter interfaces;

  Furthermore, both `__struct__` and `__changeset__` functions are
  defined so structs and changeset functionalities are available.
  """

  defmodule Metadata do
    @moduledoc """
    Stores metadata of a struct.

    The fields are:

      * `state` - the state in a struct's lifetime, e.g. :built, :loaded, :deleted
      * `source` - the database source of a model, which is the source specified
        in schema by default or custom source when building a assoc with the custom source.

    """
    defstruct [:state, :source]
  end

  @doc false
  defmacro __using__(_) do
    quote do
      import Ecto.Schema, only: [schema: 2]
      @primary_key {:id, :integer, read_after_writes: true}
      @timestamps_opts []
      @foreign_key_type :integer
    end
  end

  @doc """
  Defines a schema with a source name and field definitions.
  """
  defmacro schema(source, [do: block]) do
    quote do
      source = unquote(source)

      unless is_binary(source) do
        raise ArgumentError, "schema source must be a string, got: #{inspect source}"
      end

      Module.register_attribute(__MODULE__, :changeset_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :struct_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_assocs, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_raw, accumulate: true)

      Module.put_attribute(__MODULE__, :struct_fields,
                           {:__meta__, %Metadata{state: :built, source: source}})

      primary_key_field =
        case @primary_key do
          false ->
            []
          {name, type, opts} ->
            Ecto.Schema.field(name, type, opts)
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

      Module.eval_quoted __MODULE__, [
        Ecto.Schema.__struct__(@struct_fields),
        Ecto.Schema.__changeset__(@changeset_fields),
        Ecto.Schema.__source__(source),
        Ecto.Schema.__fields__(fields),
        Ecto.Schema.__assocs__(assocs),
        Ecto.Schema.__primary_key__(primary_key_field),
        Ecto.Schema.__load__(fields),
        Ecto.Schema.__read_after_writes__(@ecto_raw)]
    end
  end

  ## API

  @doc """
  Defines a field on the model schema with given name and type.

  ## Options

    * `:default` - Sets the default value on the schema and the struct.
      The default value is calculated at compilation time, so don't use
      expressions like `Ecto.DateTime.local` or `Ecto.UUID.generate` as
      they would then be the same for all records

    * `:virtual` - When true, the field is not persisted to the database

    * `:read_after_writes` - When true, the field is always read back
      from the repository during inserts and updates. For relational
      databases, this means the RETURNING option of those statements
      are used. For this reason, MySQL does not support this option for
      any field besides the primary key (which must be of type serial).
      Setting this option to true for MySQL will cause the values to be
      ignored or, even worse, load invalid values from the database.

  """
  defmacro field(name, type \\ :string, opts \\ []) do
    quote do
      Ecto.Schema.__field__(__MODULE__, unquote(name), unquote(type), unquote(opts))
    end
  end

  @doc """
  Generates `:inserted_at` and `:updated_at` timestamp fields.

  When using `Ecto.Model`, the fields generated by this macro
  will automatically be set to the current time when inserting
  and updating values in a repository.

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

      if inserted_at = Keyword.fetch!(timestamps, :inserted_at) do
        Ecto.Schema.field(inserted_at, Keyword.fetch!(timestamps, :type), [])
      end

      if updated_at = Keyword.fetch!(timestamps, :updated_at) do
        Ecto.Schema.field(updated_at, Keyword.fetch!(timestamps, :type), [])
      end

      @ecto_timestamps timestamps
    end
  end

  @doc """
  Defines an association.

  This macro is used by `belongs_to/3`, `has_one/3` and `has_many/3` to
  define associations. However, custom association mechanisms can be provided
  by developers and hooked in via this macro.

  Read more about custom associations in `Ecto.Association`.
  """
  defmacro association(cardinality, name, association, opts \\ []) do
    quote do
      Ecto.Schema.__association__(__MODULE__, unquote(cardinality), unquote(name),
                                  unquote(association), unquote(opts))
    end
  end

  @doc ~S"""
  Indicates a one-to-many association with another model.

  The current model has zero or more records of the other model. The other
  model often has a `belongs_to` field with the reverse association.

  ## Options

    * `:foreign_key` - Sets the foreign key, this should map to a field on the
      other model, defaults to the underscored name of the current model
      suffixed by `_id`

    * `:references` - Sets the key on the current model to be used for the
      association, defaults to the primary key on the model

    * `:through` - If this association must be defined in terms of existing
      associations. Read below for more information

  ## Examples

      defmodule Post do
        use Ecto.Model
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
        use Ecto.Model
        schema "posts" do
          has_many :comments, Comment
          has_one :permalink, Permalink
          has_many :comments_authors, through: [:comments, :author]

          # Specify the association with custom source
          has_many :tags, {"posts_tags", Tag}
        end
      end

      defmodule Comment do
        use Ecto.Model
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
  the next model `Comment`.

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
      hd(post.comments).authors #=> [%Author{...}, ...]

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
    quote bind_quoted: binding() do
      if is_list(queryable) and Keyword.has_key?(queryable, :through) do
        association(:many, name, Ecto.Association.HasThrough, queryable)
      else
        association(:many, name, Ecto.Association.Has, [queryable: queryable] ++ opts)
      end
    end
  end

  @doc ~S"""
  Indicates a one-to-one association with another model.

  The current model has zero or one records of the other model. The other
  model often has a `belongs_to` field with the reverse association.

  ## Options

    * `:foreign_key` - Sets the foreign key, this should map to a field on the
      other model, defaults to the underscored name of the current model
      suffixed by `_id`

    * `:references`  - Sets the key on the current model to be used for the
      association, defaults to the primary key on the model

    * `:through` - If this association must be defined in terms of existing
      associations. Read the section in `has_many/3` for more information

  ## Examples

      defmodule Post do
        use Ecto.Model
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
    quote bind_quoted: binding() do
      if is_list(queryable) and Keyword.has_key?(queryable, :through) do
        association(:one, name, Ecto.Association.HasThrough, queryable)
      else
        association(:one, name, Ecto.Association.Has, [queryable: queryable] ++ opts)
      end
    end
  end

  @doc ~S"""
  Indicates a one-to-one association with another model.

  The current model belongs to zero or one records of the other model. The other
  model often has a `has_one` or a `has_many` field with the reverse association.

  You should use `belongs_to` in the table that contains the foreign key. Imagine
  a company <-> manager relationship. If the company contains the `manager_id` in
  the underlying database table, we say the company belongs to manager.

  In fact, when you invoke this macro, a field with the name of foreign key is
  automatically defined in the schema for you.

  ## Options

    * `:foreign_key` - Sets the foreign key field name, defaults to the name
      of the association suffixed by `_id`. For example, `belongs_to :company`
      will define foreign key of `:company_id`

    * `:references` - Sets the key on the other model to be used for the
      association, defaults to: `:id`

    * `:auto_field` - When false, does not automatically define a `:foreign_key`
      field, implying the user is defining the field manually elsewhere

    * `:type` - Sets the type of automtically defined `:foreign_key`.
      Defaults to: `:integer` and be set per schema via `@foreign_key_type`

  All other options are forwarded to the underlying foreign key definition
  and therefore accept the same options as `field/3`.

  ## Examples

      defmodule Comment do
        use Ecto.Model
        schema "comments" do
          # This automatically defines a post_id field too
          belongs_to :post, Post

          # Specify the association with custom source
          belongs_to :author, {"posts_authors", Author}
        end
      end

      # The post can come preloaded on the comment record
      [comment] = Repo.all(from(c in Comment, where: c.id == 42, preload: :post))
      comment.post #=> %Post{...}

  """
  defmacro belongs_to(name, queryable, opts \\ []) do
    quote bind_quoted: binding() do
      opts = Keyword.put_new(opts, :foreign_key, :"#{name}_id")
      foreign_key_type = opts[:type] || @foreign_key_type
      if Keyword.get(opts, :auto_field, true) do
        field(opts[:foreign_key], foreign_key_type, opts)
      end
      association(:one, name, Ecto.Association.BelongsTo, [queryable: queryable] ++ opts)
    end
  end

  ## Callbacks

  @doc false
  def __field__(mod, name, type, opts) do
    check_type!(type, opts[:virtual])
    check_default!(type, opts[:default])

    Module.put_attribute(mod, :changeset_fields, {name, type})
    put_struct_field(mod, name, opts[:default])

    unless opts[:virtual] do
      if opts[:read_after_writes] do
        Module.put_attribute(mod, :ecto_raw, name)
      end

      Module.put_attribute(mod, :ecto_fields, {name, type})
    end
  end

  @doc false
  def __association__(mod, cardinality, name, association, opts) do
    not_loaded  = %Ecto.Association.NotLoaded{__owner__: mod,
                    __field__: name, __cardinality__: cardinality}
    put_struct_field(mod, name, not_loaded)
    opts = [cardinality: cardinality] ++ opts
    Module.put_attribute(mod, :ecto_assocs, {name, association.struct(mod, name, opts)})
  end

  @doc false
  def __load__(struct, source, fields, idx, values) do
    loaded = do_load(struct, fields, idx, values)
    loaded = Map.put(loaded, :__meta__, %Metadata{state: :loaded, source: source})
    Ecto.Model.Callbacks.__apply__(struct.__struct__, :after_load, loaded)
  end

  defp do_load(struct, fields, idx, values) when is_integer(idx) and is_tuple(values) do
    Enum.reduce(fields, {struct, idx}, fn
      {field, type}, {acc, idx} ->
        value = Ecto.Type.load!(type, elem(values, idx))
        {Map.put(acc, field, value), idx + 1}
    end) |> elem(0)
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
  def __struct__(struct_fields) do
    quote do
      defstruct unquote(Macro.escape(struct_fields))
    end
  end

  @doc false
  def __source__(source) do
    quote do
      def __schema__(:source), do: unquote(Macro.escape(source))
    end
  end

  @doc false
  def __fields__(fields) do
    quoted = Enum.map(fields, fn {name, type} ->
      quote do
        def __schema__(:field, unquote(name)), do: unquote(type)
      end
    end)

    field_names = Enum.map(fields, &elem(&1, 0))

    quoted ++ [quote do
      def __schema__(:field, _), do: nil
      def __schema__(:fields), do: unquote(field_names)
    end]
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
  def __primary_key__(primary_key) do
    quote do
      def __schema__(:primary_key), do: unquote(primary_key)
    end
  end

  @doc false
  def __load__(fields) do
    quote do
      def __schema__(:load, source, idx, values) do
        Ecto.Schema.__load__(__struct__(), source, unquote(fields), idx, values)
      end
    end
  end

  @doc false
  def __read_after_writes__(fields) do
    quote do
      def __schema__(:read_after_writes), do: unquote(Enum.reverse(fields))
    end
  end

  ## Private

  defp put_struct_field(mod, name, assoc) do
    fields = Module.get_attribute(mod, :struct_fields)

    if List.keyfind(fields, name, 0) do
      raise ArgumentError, "field/association `#{name}` is already set on schema"
    end

    Module.put_attribute(mod, :struct_fields, {name, assoc})
  end

  defp check_type!(type, virtual?) do
    cond do
      type == :any and not virtual? ->
        raise ArgumentError, "only virtual fields can have type :any"
      Ecto.Type.primitive?(type) ->
        true
      is_atom(type) ->
        if Code.ensure_compiled?(type) and function_exported?(type, :type, 0) do
          type
        else
          raise ArgumentError, "invalid or unknown field type `#{inspect type}`"
        end
      true ->
        raise ArgumentError, "invalid field type `#{inspect type}`"
    end
  end

  defp check_default!(type, default) do
    case Ecto.Type.dump(type, default) do
      {:ok, _} ->
        :ok
      :error ->
        raise ArgumentError, "invalid default argument `#{inspect default}` for `#{inspect type}`"
    end
  end
end
