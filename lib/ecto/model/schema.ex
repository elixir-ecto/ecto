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
  * `foreign_key_type` - sets the type for any `belongs_to` associations.
                         This can be overridden using the `:type` option
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

      @ecto_primary_key nil
      @ecto_source unquote(source)

      Module.register_attribute(__MODULE__, :assign_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :struct_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_fields, accumulate: true)
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
          raise ArgumentError, ":primary_key must be false or {name, type, opts}"
      end

      try do
        import Ecto.Model.Schema
        unquote(block)
      after
        :ok
      end

      fields = @ecto_fields |> Enum.reverse
      assocs = @ecto_assocs |> Enum.reverse

      def __schema__(:source), do: @ecto_source

      Module.eval_quoted __MODULE__, [
        Ecto.Model.Schema.__assign__(@assign_fields, @ecto_primary_key),
        Ecto.Model.Schema.__struct__(@struct_fields),
        Ecto.Model.Schema.__fields__(fields),
        Ecto.Model.Schema.__assocs__(__MODULE__, assocs, @ecto_primary_key, fields),
        Ecto.Model.Schema.__primary_key__(@ecto_primary_key),
        Ecto.Model.Schema.__helpers__(fields, @ecto_primary_key) ]
    end
  end

  ## API

  @doc """
  Defines a field on the model schema with given name and type, will also create
  a struct field.

  ## Options

    * `:default` - Sets the default value on the schema and the struct
    * `:virtual` - When true, the field is not persisted
    * `:primary_key` - When true, the field is set as primary key

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
    check_type!(type, opts[:virtual])

    if opts[:primary_key] do
      if pk = Module.get_attribute(mod, :ecto_primary_key) do
        raise ArgumentError, message: "primary key already defined as `#{pk}`"
      else
        Module.put_attribute(mod, :ecto_primary_key, name)
      end
    end

    Module.put_attribute(mod, :assign_fields, {name, type})
    put_struct_field(mod, name, opts[:default])

    unless opts[:virtual] do
      Module.put_attribute(mod, :ecto_fields, {name, type, opts})
    end
  end

  @doc false
  def __has_many__(mod, name, queryable, opts) do
    assoc = Ecto.Associations.HasMany.Proxy.__assoc__(:new, name, mod)
    put_struct_field(mod, name, assoc)

    opts = [queryable: queryable] ++ opts
    Module.put_attribute(mod, :ecto_assocs, {name, :has_many, opts})
  end

  @doc false
  def __has_one__(mod, name, queryable, opts) do
    assoc = Ecto.Associations.HasOne.Proxy.__assoc__(:new, name, mod)
    put_struct_field(mod, name, assoc)

    opts = [queryable: queryable] ++ opts
    Module.put_attribute(mod, :ecto_assocs, {name, :has_one, opts})
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
    put_struct_field(mod, name, assoc)

    opts = [queryable: queryable] ++ opts
    Module.put_attribute(mod, :ecto_assocs, {name, :belongs_to, opts})
  end

  defp put_struct_field(mod, name, assoc) do
    fields = Module.get_attribute(mod, :struct_fields)

    if List.keyfind(fields, name, 0) do
      raise ArgumentError, message: "field/association `#{name}` is already set on schema"
    end

    Module.put_attribute(mod, :struct_fields, {name, assoc})
  end

  ## Helpers

  @doc false
  def __assign__(assign_fields, primary_key) do
    map = assign_fields |> Enum.into(%{}) |> Map.delete(primary_key) |> Macro.escape()
    quote do
      def __assign__ do
        unquote(map)
      end
    end
  end

  @doc false
  def __struct__(struct_fields) do
    quote do
      defstruct unquote(Macro.escape(struct_fields))
    end
  end

  @doc false
  def __fields__(fields) do
    quoted = Enum.map(fields, fn {name, type, _opts} ->
      quote do
        def __schema__(:field_type, unquote(name)), do: unquote(type)
      end
    end)

    field_names = Enum.map(fields, &elem(&1, 0))

    quoted ++ [ quote do
      def __schema__(:field_type, _), do: nil
      def __schema__(:field_names), do: unquote(field_names)
    end ]
  end

  @doc false
  def __assocs__(module, assocs, primary_key, fields) do
    quoted = Enum.map(assocs, fn {name, type, opts} ->
      pk = opts[:references] || primary_key

      if is_nil(pk) do
        raise ArgumentError, message: "need to set :references option for " <>
          "association #{inspect name} when model has no primary key"
      end

      if type in [:has_many, :has_one] do
        unless List.keyfind(fields, pk, 0) do
          raise ArgumentError, message: "model does not have the field #{inspect pk} used by " <>
            "association #{inspect name}, please set the :references option accordingly"
        end
      end

      refl = Ecto.Associations.create_reflection(type, name,
        module, pk, opts[:queryable], opts[:foreign_key])

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
  def __helpers__(fields, primary_key) do
    field_names = Enum.map(fields, &elem(&1, 0))

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

        values = Map.take(model, unquote(field_names))

        Map.to_list(if keep_pk do
          values
        else
          Map.delete(values, primary_key)
        end)
      end
    end
  end

  defp check_type!(type, virtual?) do
    cond do
      type == :any and not virtual? ->
        raise ArgumentError, "only virtual fields can have type :any"
      Ecto.Query.Types.primitive?(type) ->
        true
      true ->
        raise ArgumentError, "unknown field type `#{inspect type}`"
    end
  end
end
