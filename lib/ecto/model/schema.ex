defmodule Ecto.Model.Schema do
  @moduledoc """
  Defines a schema for a model.

  A schema is a struct with associated metadata that is persisted to a
  repository. Every schema model is also a struct, that means that you work
  with models just like you would work with structs.

  ## Example

      defmodule User do
        use Ecto.Model.Schema

        schema "users" do
          field :name, :string
          field :age, :integer, default: 0
          has_many :posts, Post
        end
      end

  This module also automatically imports `from/2` from `Ecto.Query`
  as a convenience.

  ## Schema defaults

  When using the block syntax, the created model uses the default
  of a primary key named `:id`, of type `:integer`. This can be
  customized by passing `primary_key: false` to schema:

      schema "weather", primary_key: false do
        ...
      end

  Or by passing a tuple in the format `{field, type, opts}`:

      schema "weather", primary_key: {:custom_field, :string, []} do
        ...
      end

  Implicit defaults can be specified via the `@schema_defaults` attribute.
  This is useful if you want to use a different default primary key
  through your entire application.

  The supported options are:

  * `primary_key` - either `false`, or a `{field, type, opts}` tuple
  * `foreign_key_type` - sets the type for any belongs_to associations.
                         This can be overrided using the `:type` option
                         to the `belongs_to` statement. Defaults to
                         type `:integer`

  ## Example

      defmodule MyApp.Model do
        defmacro __using__(_) do
          quote do
            @schema_defaults primary_key: {:uuid, :string, []},
                             foreign_key_type: :string
            use Ecto.Model
          end
        end
      end

      defmodule MyApp.Post do
        use MyApp.Model
        schema "posts" do
          has_many :comments, MyApp.Comment
        end
      end

      defmodule MyApp.Comment do
        use MyApp.Model
        schema "comments" do
          belongs_to :post, MyApp.Comment
        end
      end

  Any models using `MyApp.Model will get the `:uuid` field, with type
  `:string` as the primary key.

  The `belongs_to` association on `MyApp.Comment` will also now require
  that `:post_id` be of `:string` type to reference the `:uuid` of a
  `MyApp.Post` model.

  ## Setting Primary Keys with Schema Defaults

  In the example above, the `:uuid` primary key field needs to be
  explicitly set by the developer before the Model can be inserted
  or updated in a database.

  To set a primary key, the developer **must** call the function
  `Ecto.Model.put_primary_key/2`.

  Example:

      uuid = "some_uuid"

      # Don't do this
      post = %MyApp.Post{uuid: uuid}

      # Do this instead
      post = Ecto.Model.put_primary_key(%MyApp.Post{}, uuid)

  This must be done in order to ensure that any associations of the Model
  are appropriately updated.

  ## Reflection

  Any schema module will generate the `__schema__` function that can be used for
  runtime introspection of the schema.

  * `__schema__(:source)` - Returns the source as given to `schema/2`;
  * `__schema__(:field, field)` - Returns the options for the given field;
  * `__schema__(:field_type, field)` - Returns the type of the given field;
  * `__schema__(:field_names)` - Returns a list of all field names;
  * `__schema__(:associations)` - Returns a list of all association field names;
  * `__schema__(:association, field)` - Returns the given field's association
                                        reflection;
  * `__schema__(:primary_key)` - Returns the field that is the primary key or
                                 `nil` if there is none;
  * `__schema__(:allocate, values)` - Creates a new model struct from the given
                                      field values;
  * `__schema__(:keywords, model)` - Return a keyword list of all non-virtual
                                     fields and their values;

  """

  require Ecto.Query.Util, as: Util

  @doc false
  defmacro __using__(_) do
    quote do
      # TODO: Move those imports out to Ecto.Model
      import Ecto.Query, only: [from: 2]
      import Ecto.Model, only: [primary_key: 1, put_primary_key: 2, scoped: 2]
      import Ecto.Model.Schema, only: [schema: 2, schema: 3]
    end
  end

  @doc """
  Defines a schema with a source name and field definitions.
  """
  defmacro schema(source, opts \\ [], block)

  defmacro schema(source, opts, [do: block]) do
    quote do
      opts = (Module.get_attribute(__MODULE__, :schema_defaults) || [])
             |> Keyword.merge(unquote(opts))

      @ecto_fields []
      @struct_fields []
      @ecto_primary_key nil
      @ecto_source unquote(source)
      Module.register_attribute(__MODULE__, :ecto_assocs, accumulate: true)

      @ecto_foreign_key_type opts[:foreign_key_type]

      case opts[:primary_key] do
        nil ->
          Ecto.Model.Schema.field(:id, :integer, primary_key: true)
        false ->
          :ok
        {name, type, opts} ->
          Ecto.Model.Schema.field(name, type, Keyword.put(opts, :primary_key, true))
        other ->
          raise ArgumentError, message: ":primary_key must be false or {name, type, opts}"
      end

      import Ecto.Model.Schema, only: [field: 1, field: 2, field: 3, has_many: 2,
          has_many: 3, has_one: 2, has_one: 3, belongs_to: 2, belongs_to: 3]
      unquote(block)
      import Ecto.Model.Schema, only: []

      all_fields = @ecto_fields |> Enum.reverse
      assocs     = @ecto_assocs |> Enum.reverse

      fields = Enum.filter(all_fields, fn {_, opts} -> opts[:type] != :virtual end)

      def __schema__(:source), do: @ecto_source

      Module.eval_quoted __MODULE__, [
        Ecto.Model.Schema.ecto_struct(@struct_fields),
        Ecto.Model.Schema.ecto_queryable(@ecto_source, __MODULE__),
        Ecto.Model.Schema.ecto_fields(fields),
        Ecto.Model.Schema.ecto_assocs(assocs, @ecto_primary_key, fields),
        Ecto.Model.Schema.ecto_primary_key(@ecto_primary_key),
        Ecto.Model.Schema.ecto_helpers(fields, all_fields, @ecto_primary_key) ]
    end
  end

  ## API

  @doc """
  Defines a field on the model schema with given name and type, will also create
  a struct field. If the type is `:virtual` it wont be persisted.

  ## Options

    * `:default` - Sets the default value on the schema and the struct;
    * `:primary_key` - Sets the field to be the primary key, the default
      primary key have to be overridden by setting its name to `nil`;
  """
  defmacro field(name, type \\ :string, opts \\ []) do
    quote do
      Ecto.Model.Schema.__field__(__MODULE__, unquote(name), unquote(type), unquote(opts))
    end
  end

  @doc ~S"""
  Indicates a one-to-many association with another model, where the current
  model has zero or more records of the other model. The other model often
  has a `belongs_to` field with the reverse association.

  Creates a virtual field called `name`. The association can be accessed via
  this field, see `Ecto.Associations.HasMany` for more information. See the
  examples to see how to perform queries on the association and
  `Ecto.Query.join/3` for joins.

  ## Options

    * `:foreign_key` - Sets the foreign key, this should map to a field on the
                       other model, defaults to: `:"#{model}_id"`;
    * `:references`  - Sets the key on the current model to be used for the
                       association, defaults to the primary key on the model;

  ## Examples

      defmodule Post do
        schema "posts" do
          has_many :comments, Comment
        end
      end

      # Get all comments for a given post
      post = Repo.get(Post, 42)
      comments = Repo.all(post.comments)

      # The comments can come preloaded on the post struct
      [post] = Repo.all(from(p in Post, where: p.id == 42, preload: :comments))
      post.comments.all #=> [ %Comment{...}, ... ]

      # Or via an association join
      [post] = Repo.all(from(p in Post,
                      where: p.id == 42,
                  left_join: c in p.comments,
                     select: assoc(p, c)))
      post.comments.all #=> [ %Comment{...}, ... ]
  """
  defmacro has_many(name, queryable, opts \\ []) do
    quote do
      Ecto.Model.Schema.__has_many__(__MODULE__, unquote(name), unquote(queryable), unquote(opts))
    end
  end

  @doc ~S"""
  Indicates a one-to-one association with another model, where the current model
  has zero or one records of the other model. The other model often has a
  `belongs_to` field with the reverse association.

  Creates a virtual field called `name`. The association can be accessed via
  this field, see `Ecto.Associations.HasOne` for more information. Check the
  examples to see how to perform queries on the association and
  `Ecto.Query.join/3` for joins.

  ## Options

    * `:foreign_key` - Sets the foreign key, this should map to a field on the
                       other model, defaults to: `:"#{model}_id"`;
    * `:references`  - Sets the key on the current model to be used for the
                       association, defaults to the primary key on the model;

  ## Examples

      defmodule Post do
        schema "posts" do
          has_one :permalink, Permalink
        end
      end

      # The permalink can come preloaded on the post record
      [post] = Repo.all(from(p in Post, where: p.id == 42, preload: :permalink))
      post.permalink.get #=> %Permalink{...}

      # Or via an association join
      [post] = Repo.all(from(p in Post,
                      where: p.id == 42,
                  left_join: pl in p.permalink,
                     select: assoc(p, pl)))
      post.permalink.get #=> %Permalink{...}
  """
  defmacro has_one(name, queryable, opts \\ []) do
    quote do
      Ecto.Model.Schema.__has_one__(__MODULE__, unquote(name), unquote(queryable), unquote(opts))
    end
  end

  @doc ~S"""
  Indicates a one-to-one association with another model, the current model
  belongs to zero or one records of the other model. The other model
  often has a `has_one` or a `has_many` field with the reverse association.
  Compared to `has_one` this association should be used where you would place
  the foreign key on an SQL table.

  Creates a virtual field called `name`. The association can be accessed via
  this field, see `Ecto.Associations.BelongsTo` for more information. Check the
  examples to see how to perform queries on the association and
  `Ecto.Query.join/3` for joins.

  ## Options

    * `:foreign_key` - Sets the foreign key field name, defaults to:
                       `:"#{other_model}_id"`;
    * `:references`  - Sets the key on the other model to be used for the
                       association, defaults to: `:id`;
    * `:type`        - Sets the type of `:foreign_key`. Defaults to: `:integer`;

  ## Examples

      defmodule Comment do
        schema "comments" do
          belongs_to :post, Post
        end
      end

      # The post can come preloaded on the comment record
      [comment] = Repo.all(from(c in Comment, where: c.id == 42, preload: :post))
      comment.post.get #=> %Post{...}

      # Or via an association join
      [comment] = Repo.all(from(c in Comment,
                         where: c.id == 42,
                     left_join: p in c.post,
                        select: assoc(c, p)))
      comment.post.get #=> %Post{...}
  """
  defmacro belongs_to(name, queryable, opts \\ []) do
    quote do
      Ecto.Model.Schema.__belongs_to__(__MODULE__, unquote(name), unquote(queryable), unquote(opts))
    end
  end

  ## Callbacks

  # TODO: Check that the opts are valid for the given type,
  # especially check the default value
  @doc false
  def __field__(mod, name, type, opts) do
    check_type!(type)
    fields = Module.get_attribute(mod, :ecto_fields)

    if opts[:primary_key] do
      if pk = Module.get_attribute(mod, :ecto_primary_key) do
        raise ArgumentError, message: "primary key already defined as `#{pk}`"
      else
        Module.put_attribute(mod, :ecto_primary_key, name)
      end
    end

    clash = Enum.any?(fields, fn {prev, _} -> name == prev end)
    if clash do
      raise ArgumentError, message: "field `#{name}` was already set on schema"
    end

    struct_fields = Module.get_attribute(mod, :struct_fields)
    Module.put_attribute(mod, :struct_fields, struct_fields ++ [{name, opts[:default]}])

    opts = Enum.reduce([:default, :primary_key], opts, &Dict.delete(&2, &1))
    Module.put_attribute(mod, :ecto_fields, [{name, [type: type] ++ opts}|fields])
  end

  @doc false
  def __has_many__(mod, name, queryable, opts) do
    assoc = Ecto.Associations.HasMany.Proxy.__assoc__(:new, name, mod)
    __field__(mod, name, :virtual, default: assoc)

    opts = [type: :has_many, queryable: queryable] ++ opts
    Module.put_attribute(mod, :ecto_assocs, {name, opts})
  end

  @doc false
  def __has_one__(mod, name, queryable, opts) do
    assoc = Ecto.Associations.HasOne.Proxy.__assoc__(:new, name, mod)
    __field__(mod, name, :virtual, default: assoc)

    opts = [type: :has_one, queryable: queryable] ++ opts
    Module.put_attribute(mod, :ecto_assocs, {name, opts})
  end

  @doc false
  def __belongs_to__(mod, name, queryable, opts) do
    opts = opts
           |> Keyword.put_new(:references, :id)
           |> Keyword.put_new(:foreign_key, :"#{name}_id")

    foreign_key_type =
      opts[:type] || Module.get_attribute(mod, :ecto_foreign_key_type) || :integer

    __field__(mod, opts[:foreign_key], foreign_key_type, [])

    assoc = Ecto.Associations.BelongsTo.Proxy.__assoc__(:new, name, mod)
    __field__(mod, name, :virtual, default: assoc)

    opts = [type: :belongs_to, queryable: queryable] ++ opts
    Module.put_attribute(mod, :ecto_assocs, {name, opts})
  end

  ## Helpers

  @doc false
  def ecto_struct(struct_fields) do
    quote do
      defstruct unquote(Macro.escape(struct_fields))
    end
  end

  @doc false
  def ecto_queryable(source, module) do
    quote do
      def __queryable__ do
        %Ecto.Query{from: {unquote(source), unquote(module)}}
      end
    end
  end

  @doc false
  def ecto_fields(fields) do
    quoted = Enum.map(fields, fn {name, opts} ->
      quote do
        def __schema__(:field, unquote(name)), do: unquote(opts)
        def __schema__(:field_type, unquote(name)), do: unquote(opts[:type])
      end
    end)

    field_names = Enum.map(fields, &elem(&1, 0))
    quoted ++ [ quote do
      def __schema__(:field, _), do: nil
      def __schema__(:field_type, _), do: nil
      def __schema__(:field_names), do: unquote(field_names)
    end ]
  end

  @doc false
  def ecto_assocs(assocs, primary_key, fields) do
    quoted = Enum.map(assocs, fn {name, opts} ->
      quote bind_quoted: [name: name, opts: opts, primary_key: primary_key, fields: fields] do
        pk = opts[:references] || primary_key

        if nil?(pk) do
          raise ArgumentError, message: "need to set `references` option for " <>
            "association when model has no primary key"
        end

        if opts[:type] in [:has_many, :has_one] do
          unless Enum.any?(fields, fn {name, _} -> pk == name end) do
            raise ArgumentError, message: "`references` option on association " <>
              "doesn't match any field on the model"
          end
        end

        refl = Ecto.Associations.create_reflection(opts[:type], name,
          __MODULE__, pk, opts[:queryable], opts[:foreign_key])

        def __schema__(:association, unquote(name)) do
          unquote(Macro.escape(refl))
        end
      end
    end)

    quote do
      def __schema__(:associations), do: unquote(Keyword.keys(assocs))

      unquote(quoted)
      def __schema__(:association, _), do: nil
    end
  end

  @doc false
  def ecto_primary_key(primary_key) do
    quote do
      def __schema__(:primary_key), do: unquote(primary_key)
    end
  end

  @doc false
  def ecto_helpers(fields, all_fields, primary_key) do
    field_names = Enum.map(fields, &elem(&1, 0))
    all_field_names = Enum.map(all_fields, &elem(&1, 0))

    quote do
      # TODO: This can be optimized
      def __schema__(:allocate, values) do
        zip   = Enum.zip(unquote(field_names), values)
        pk    = Dict.get(zip, unquote(primary_key))
        model = struct(__MODULE__, zip)

        if pk, do: model = Ecto.Model.put_primary_key(model, pk)
        model
      end

      def __schema__(:keywords, model, opts \\ []) do
        keep_pk     = Keyword.get(opts, :primary_key, true)
        primary_key = unquote(primary_key)

        values = Map.take(model, unquote(all_field_names))

        Enum.filter(values, fn {field, _} ->
          __schema__(:field, field) && (keep_pk or field != primary_key)
        end)
      end
    end
  end

  defp check_type!({outer, inner}) when outer in Util.poly_types and inner in Util.types, do: :ok

  defp check_type!(type) when type in Util.types, do: :ok

  defp check_type!(type) do
    raise ArgumentError, message: "`#{Macro.to_string(type)}` is not a valid field type"
  end
end
