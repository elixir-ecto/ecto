defmodule Ecto.Entity do
  @moduledoc """
  This module is used to define an entity. An entity is a record with associated
  meta data that is persisted to a repository.

  Every entity is also a record, that means that you work with entities just
  like you would work with records, to set the default values for the record
  fields the `default` option is set in the `field` options.

  ## Example

      defmodule User do
        use Ecto.Entity

        field :name, :string
        field :age, :integer
        has_many :posts, Post
      end

      defmodule Post do
        use Ecto.Entity

        field :text, :string
        belongs_to :author, User
      end

  Accessors and updater functions for the primary key will be generated on the
  entity, specifically `primary_key/1`, `primary_key/2` and
  `update_primary_key/2`.
  """

  ## API

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
      Ecto.Entity.__field__(__MODULE__, unquote(name), unquote(type), unquote(opts))
    end
  end

  @doc """
  Creates a virtual field with the default value `Ecto.Associations.HasMany`.

  Indicates a one-to-many association with another queryable, where this entity
  has zero or more records of the queryable structure. The other queryable often
  has a `belongs_to` field with the reverse association.

  ## Options

    * `:foreign_key` - Sets the foreign key that is used on the other entity;
    * `:primary_key` - Sets the key on the current entity to be used for the
                       association;
  """
  defmacro has_many(name, queryable, opts // []) do
    quote do
      Ecto.Entity.__has_many__(__MODULE__, unquote(name), unquote(queryable), unquote(opts))
    end
  end

  @doc """
  Creates a virtual field with the default value `Ecto.Associations.HasOne`.

  Indicates a one-to-one association with another queryable, where this entity
  has zero or one records of the queryable structure. The other queryable often
  has a `belongs_to` field with the reverse association.

  ## Options

    * `:foreign_key` - Sets the foreign key that is used on the other entity;
    * `:primary_key` - Sets the key on the current entity to be used for the
                       association;
  """
  defmacro has_one(name, queryable, opts // []) do
    quote do
      Ecto.Entity.__has_one__(__MODULE__, unquote(name), unquote(queryable), unquote(opts))
    end
  end

  @doc """
  Creates a virtual field with the default value `Ecto.Associations.BelongsTo`.

  Indiciates a one-to-one association with another queryable, this entity
  belongs to zero or one records of the queryable structure.

  This function will also generate a foreign key field.

  ## Options

    * `:foreign_key` - Sets the foreign key field name;
    * `:primary_key` - Sets the key on the other entity to be used for the
                       association;
  """
  defmacro belongs_to(name, queryable, opts // []) do
    quote do
      Ecto.Entity.__belongs_to__(__MODULE__, unquote(name), unquote(queryable), unquote(opts))
    end
  end

  ## Callbacks

  @types %w(string integer float binary list datetime interval virtual)a

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      import Ecto.Entity

      @before_compile Ecto.Entity
      @ecto_fields []
      @record_fields []
      @ecto_primary_key nil
      Module.register_attribute(__MODULE__, :ecto_assocs, accumulate: true)

      @ecto_model opts[:model]
      field(:model, :virtual, default: opts[:model])

      case opts[:primary_key] do
        nil ->
          field(:id, :integer, primary_key: true)
        false ->
          :ok
        { name, type } ->
          field(name, type, primary_key: true)
        other ->
          raise ArgumentError, message: ":primary_key must be false, nil or { name, type }"
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    mod = env.module

    primary_key = Module.get_attribute(mod, :ecto_primary_key)
    all_fields  = Module.get_attribute(mod, :ecto_fields) |> Enum.reverse
    assocs      = Module.get_attribute(mod, :ecto_assocs) |> Enum.reverse

    record_fields = Module.get_attribute(mod, :record_fields)
    Record.deffunctions(record_fields, env)

    fields = Enum.filter(all_fields, fn({ _, opts }) -> opts[:type] != :virtual end)

    [ ecto_fields(fields),
      ecto_assocs(assocs, primary_key),
      ecto_primary_key(primary_key),
      ecto_helpers(fields, all_fields) ]
  end

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

    clash = Enum.any?(fields, fn({ prev, _ }) -> name == prev end)
    if clash do
      raise ArgumentError, message: "field `#{name}` was already set on entity"
    end

    record_fields = Module.get_attribute(mod, :record_fields)
    Module.put_attribute(mod, :record_fields, record_fields ++ [{ name, opts[:default] }])

    opts = Enum.reduce([:default, :primary_key], opts, &Dict.delete(&2, &1))
    Module.put_attribute(mod, :ecto_fields, [{ name, [type: type] ++ opts }|fields])
  end

  @doc false
  def __has_many__(mod, name, queryable, opts) do
    check_foreign_key!(mod, opts[:foreign_key])

    assoc = Ecto.Associations.HasMany.__ecto__(:new, name)
    __field__(mod, :"__#{name}__", :virtual, default: assoc)

    opts = [type: :has_many, queryable: queryable]
    Module.put_attribute(mod, :ecto_assocs, { name, opts })
  end

  @doc false
  def __has_one__(mod, name, queryable, opts) do
    check_foreign_key!(mod, opts[:foreign_key])

    assoc = Ecto.Associations.HasOne.__ecto__(:new, name)
    __field__(mod, :"__#{name}__", :virtual, default: assoc)

    opts = [type: :has_one, queryable: queryable]
    Module.put_attribute(mod, :ecto_assocs, { name, opts })
  end

  @doc false
  def __belongs_to__(mod, name, queryable, opts) do
    assoc_name  = queryable |> Module.split |> List.last |> String.downcase
    primary_key = opts[:primary_key] || :id
    foreign_key = opts[:foreign_key] || :"#{assoc_name}_#{primary_key}"
    __field__(mod, foreign_key, :integer, [])

    assoc = Ecto.Associations.BelongsTo.__ecto__(:new, name)
    __field__(mod, :"__#{name}__", :virtual, default: assoc)

    opts = [ type: :belongs_to, queryable: queryable,
             foreign_key: foreign_key, primary_key: primary_key ]
    Module.put_attribute(mod, :ecto_assocs, { name, opts })
  end

  ## Helpers

  defp check_type!({ outer, inner }) when is_atom(outer) do
    check_type!(outer)
    check_type!(inner)
  end

  defp check_type!(type) do
    unless type in @types do
      raise ArgumentError, message: "`#{Macro.to_string(type)}` is not a valid field type"
    end
  end

  defp check_foreign_key!(mod, foreign_key) do
    model = Module.get_attribute(mod, :ecto_model)
    if nil?(model) and nil?(foreign_key) do
      raise ArgumentError, message: "need to set `foreign_key` option for
        assocation when model name can't be infered"
    end
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
        pk = opts[:primary_key] || primary_key

        refl = Ecto.Associations.create_reflection(opts[:type], name, @ecto_model,
          __MODULE__, pk, opts[:queryable], opts[:foreign_key])

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
