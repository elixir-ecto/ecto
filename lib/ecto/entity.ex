defmodule Ecto.Entity do
  @moduledoc """
  This module is used to define an entity. An entity is a record with associated
  meta data that will be used when creating and running queries. See
  `Ecto.Entity.Dataset` for more information about the specific functions used
  to specify an entity.

  Every entity is also a record, that means that you work with entities just
  like you would work with records, to set the default values for the record
  fields the `default` option is set in the `field` options.

  ## Example

      defmodule User do
        use Ecto.Entity

        dataset do
          field :name, :string
          field :age, :integer
          has_many :posts, Post
        end
      end

      defmodule Post do
        use Ecto.Entity

        dataset do
          field :text, :string
          belongs_to :author, User
        end
      end

  Accessors and updater functions for the primary key will be generated on the
  entity, specifically `primary_key/1`, `primary_key/2` and
  `update_primary_key/2`.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Ecto.Entity
      @before_compile unquote(__MODULE__)
      @ecto_dataset false
      @ecto_model nil
    end
  end

  @doc """
  Defines the entity dataset. Takes an optional primary key name, if none is
  given, defaults to `:id`, pass `nil` if there should be no primary key.
  """
  defmacro dataset(primary_key // :id, block) do
    quote do
      try do
        import Ecto.Entity.Dataset

        @ecto_primary_key nil
        @ecto_fields []
        Module.register_attribute(__MODULE__, :ecto_assocs, accumulate: true)

        if @ecto_dataset do
          raise ArgumentError, message: "dataset already defined"
        end
        @ecto_dataset true

        field(:model, :virtual, default: @ecto_model)

        result = unquote(block)

        primary_key = unquote(primary_key)
        if primary_key && (!@ecto_primary_key || (@ecto_primary_key && primary_key != :id)) do
          field(primary_key, :integer, [primary_key: true], -2)
        end

        record_fields = @ecto_fields
          |> Enum.reverse
          |> Enum.map(fn({ field, opts }) -> { field, opts[:default] } end)

        @record_fields record_fields
        Record.deffunctions(record_fields, __ENV__)
        Ecto.Entity.deffunctions(__ENV__)

        result
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    unless Module.get_attribute(env.module, :ecto_dataset) do
      raise ArgumentError, message: "dataset not defined, an entity has to " <>
        "define a dataset, see `Ecto.Entity.Dataset`"
    end
  end

  @doc false
  def deffunctions(env) do
    primary_key = Module.get_attribute(env.module, :ecto_primary_key)
    all_fields  = Module.get_attribute(env.module, :ecto_fields) |> Enum.reverse
    assocs      = Module.get_attribute(env.module, :ecto_assocs) |> Enum.reverse
    fields = Enum.filter(all_fields, fn({ _, opts }) -> opts[:type] != :virtual end)

    contents = [
      ecto_fields(fields),
      ecto_assocs(assocs, primary_key),
      ecto_primary_key(primary_key),
      ecto_helpers(fields, all_fields) ]
    Module.eval_quoted(env.module, contents, [], env)
  end

  defp ecto_fields(fields) do
    quoted = Enum.map(fields, fn({ name, opts }) ->
      quote do
        def __ecto__(:field, unquote(name)), do: unquote(opts)
        def __ecto__(:field_type, unquote(name)), do: unquote(opts[:type])
      end
    end)

    field_names = Enum.map(fields, &elem(&1, 0))
    quoted ++ [ quote do
      def __ecto__(:field, _), do: nil
      def __ecto__(:field_type, _), do: nil
      def __ecto__(:field_names), do: unquote(field_names)
    end ]
  end

  defp ecto_assocs(assocs, primary_key) do
    quoted = Enum.map(assocs, fn({ name, opts, }) ->
      quote bind_quoted: [name: name, opts: opts, primary_key: primary_key] do
        module = @ecto_model || __MODULE__
        refl = Ecto.Associations.create_reflection(opts[:type], name, module,
          primary_key, opts[:entity], opts[:foreign_key])

        def __ecto__(:association, unquote(name)) do
          unquote(refl |> Macro.escape)
        end

        def unquote(name)(self) do
          assoc = unquote(:"__#{name}__")(self)
          assoc.__ecto__(:target, self)
        end
      end
    end)

    quoted ++ [ quote do
      def __ecto__(:association, _), do: nil
    end ]
  end

  defp ecto_primary_key(primary_key) do
    quote do
      def __ecto__(:primary_key), do: unquote(primary_key)

      if unquote(primary_key) do
        def primary_key(record), do: unquote(primary_key)(record)
        def primary_key(value, record), do: unquote(primary_key)(value, record)
        def update_primary_key(fun, record), do: unquote(:"update_#{primary_key}")(fun, record)
      else
        def primary_key(_record), do: nil
        def primary_key(_value, record), do: record
        def update_primary_key(_fun, record), do: record
      end
    end
  end

  defp ecto_helpers(fields, all_fields) do
    field_names = Enum.map(fields, &elem(&1, 0))
    all_field_names = Enum.map(all_fields, &elem(&1, 0))

    quote do
      # TODO: This can be optimized
      def __ecto__(:allocate, values) do
        zip = Enum.zip(unquote(field_names), values)
        __MODULE__.new(zip)
      end

      def __ecto__(:entity_kw, entity, opts // []) do
        filter_pk = opts[:primary_key] == false
        primary_key = __ecto__(:primary_key)

        [_module|values] = tuple_to_list(entity)
        zipped = Enum.zip(unquote(all_field_names), values)

        Enum.filter(zipped, fn { field, _ } ->
          __ecto__(:field, field) &&
            (not filter_pk || (filter_pk && field != primary_key))
        end)
      end
    end
  end
end

defmodule Ecto.Entity.Dataset do
  @moduledoc """
  This module contains all macros used to define the dataset for an entity.
  """

  @types [ :string, :integer, :float, :binary, :list, :datetime, :virtual ]

  @doc """
  Defines a field on the entity with given name and type, will also create a
  record field. If the type is `:virtual` it wont be persisted.

  ## Options

    * `:default` - Sets the default value on the entity and the record;
    * `:primary_key` - Sets the field to be the primary key, the default
      primary key have to be overridden by setting its name to `nil`, see
      `Ecto.Entity.dataset`;
  """
  defmacro field(name, type, opts // []) do
    quote do
      field(unquote(name), unquote(type), unquote(opts), 0)
    end
  end

  @doc """
  Creates a virtual field with the default value `Ecto.Associations.HasMany`.

  Indicates a one-to-many association with another entity, this entity has zero
  or more records of the other entity. The other entity often has a `belongs_to`
  field to the current entity.

  ## Options

    * `:foreign_key` - Sets the foreign key that is used on the other entity;
  """
  defmacro has_many(name, entity, opts // []) do
    quote do
      name = unquote(name)
      assoc = Ecto.Associations.HasMany.__ecto__(:new, name)
      field(:"__#{name}__", :virtual, default: assoc)
      opts = [type: :has_many, entity: unquote(entity)] ++ unquote(opts)
      @ecto_assocs { name, opts }
    end
  end

  @doc """
  Creates a virtual field with the default value `Ecto.Associations.HasOne`.

  Indicates a one-to-one association with another entity, this entity has zero
  or one records of the other entity. The other entity often has a `belongs_to`
  field to the current entity.

  ## Options

    * `:foreign_key` - Sets the foreign key that is used on the other entity;
  """
  defmacro has_one(name, entity, opts // []) do
    quote do
      name = unquote(name)
      assoc = Ecto.Associations.HasOne.__ecto__(:new, name)
      field(:"__#{name}__", :virtual, default: assoc)
      opts = [type: :has_one, entity: unquote(entity)] ++ unquote(opts)
      @ecto_assocs { name, opts }
    end
  end

  @doc """
  Creates a virtual field with the default value `Ecto.Associations.BelongsTo`.

  Indiciates a one-to-one association with another entity, this entity belongs
  to zero or one records of the other entity. The other entity often has a
  `has_many` or `has_one` field to the current entity. Will also generate a
  foreign key field.

  ## Options

    * `:foreign_key` - Sets the foreign key field name;
  """
  defmacro belongs_to(name, entity, opts // []) do
    quote do
      name = unquote(name)
      entity = unquote(entity)
      opts = unquote(opts)

      assoc_name = entity |> Module.split |> List.last |> String.downcase
      foreign_key = opts[:foreign_key] || :"#{assoc_name}_id"
      field(foreign_key, :integer)

      assoc = Ecto.Associations.BelongsTo.__ecto__(:new, name)
      field(:"__#{name}__", :virtual, default: assoc)
      opts = [type: :belongs_to, entity: entity, foreign_key: foreign_key] ++ opts
      @ecto_assocs { name, opts }
    end
  end

  @doc false
  defmacro field(name, type, opts, pos) do
    # TODO: Check that the opts are valid for the given type, especially check
    # the default value

    quote do
      field_name = unquote(name)
      type = unquote(type)
      field_opts = unquote(opts)
      Ecto.Entity.Dataset.check_type(type)

      clash = Enum.any?(@ecto_fields, fn({ prev_name, _ }) -> field_name == prev_name end)
      if clash do
        raise ArgumentError, message: "field `#{field_name}` was already set on entity"
      end

      if field_opts[:primary_key] do
        if @ecto_primary_key do
          raise ArgumentError, message: "there can only be one primary key"
        end
        @ecto_primary_key field_name
      end

      pos = unquote(pos)
      @ecto_fields List.insert_at(@ecto_fields, pos, { field_name, [type: type] ++ field_opts })
    end
  end

  @doc false
  def check_type({ outer, inner }) when is_atom(outer) do
    check_type(outer)
    check_type(inner)
  end

  def check_type(type) do
    unless type in @types do
      raise ArgumentError, message: "`#{Macro.to_string(type)}` is not a valid field type"
    end
  end
end
