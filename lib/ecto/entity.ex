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

        dataset "users" do
          field :name, :string
          field :age, :integer
        end
      end

  Accessors and updater functions for the primary key will be generated on the
  entity, specifically `primary_key/1`, `primary_key/2` and
  `update_primary_key/2`.
  """

  @doc """
  Defines the entity dataset. Takes an optional primary key name, if none is
  given, defaults to `:id`, pass `nil` if there should be no primary key.
  """
  defmacro dataset(name, primary_key // :id, block) do
    quote do
      primary_key = unquote(primary_key)

      try do
        import Ecto.Entity.Dataset

        primary_key = unquote(primary_key)

        if Module.get_attribute(__MODULE__, :ecto_dataset) do
          raise ArgumentError, message: "dataset already defined"
        end

        @ecto_dataset unquote(name)
        @ecto_primary_key nil

        if primary_key do
          field(primary_key, :integer, primary_key: true)
        end

        result = unquote(block)

        record_fields = @ecto_fields
          |> Enum.reverse
          |> Enum.map(fn({ field, opts }) -> { field, opts[:default] } end)

        @record_fields record_fields
        Record.deffunctions(record_fields, __ENV__)

        result
      end
    end
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Ecto.Entity, only: [dataset: 2, dataset: 3]
      @before_compile unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :ecto_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_assocs, accumulate: true)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    module        = env.module
    dataset_name  = Module.get_attribute(module, :ecto_dataset)
    primary_key   = Module.get_attribute(module, :ecto_primary_key)
    all_fields    = Module.get_attribute(module, :ecto_fields) |> Enum.reverse
    assocs        = Module.get_attribute(module, :ecto_assocs) |> Enum.reverse

    unless dataset_name do
      raise ArgumentError, message: "dataset not defined, an entity has to " <>
        "define a dataset, see `Ecto.Entity.Dataset`"
    end

    fields = Enum.filter(all_fields, fn({ _, opts }) -> opts[:type] != :virtual end)
    all_field_names = Enum.map(all_fields, &elem(&1, 0))
    field_names = Enum.map(fields, &elem(&1, 0))

    fields_quote = Enum.map(fields, fn({ name, opts }) ->
      quote do
        def __ecto__(:field, unquote(name)), do: unquote(opts)
        def __ecto__(:field_type, unquote(name)), do: unquote(opts[:type])
      end
    end)

    assocs_quote = Enum.map(assocs, fn({ name, opts, }) ->
      quote bind_quoted: [name: name, opts: opts, primary_key: primary_key] do
        entity = opts[:entity]
        module_name = __MODULE__ |> Module.split |> List.last |> String.downcase
        foreign_key = opts[:foreign_key] || :"#{module_name}_#{primary_key}"
        refl = Ecto.Reflections.HasMany[owner: __MODULE__, associated: entity,
          foreign_key: foreign_key, field: :"__#{name}__"] |> Macro.escape

        def __ecto__(:association, unquote(name)) do
          unquote(refl)
        end

        def unquote(name)(self) do
          assoc = unquote(:"__#{name}__")(self)
          assoc.__target__(self)
        end
      end
    end)

    quote do
      def __ecto__(:dataset), do: unquote(dataset_name)
      def __ecto__(:primary_key), do: unquote(primary_key)
      def __ecto__(:field_names), do: unquote(field_names)
      unquote(fields_quote)
      def __ecto__(:field, _), do: nil
      def __ecto__(:field_type, _), do: nil

      if unquote(primary_key) do
        def primary_key(record), do: unquote(primary_key)(record)
        def primary_key(value, record), do: unquote(primary_key)(value, record)
        def update_primary_key(fun, record), do: unquote(:"update_#{primary_key}")(fun, record)
      else
        def primary_key(_record), do: nil
        def primary_key(_value, record), do: record
        def update_primary_key(_fun, record), do: record
      end

      unquote(assocs_quote)
      def __ecto__(:association, _), do: nil

      # TODO: This can be optimized
      def __ecto__(:allocate, values) do
        zip = Enum.zip(unquote(field_names), values)
        __MODULE__.new(zip)
      end

      # def __ecto__(:zip_kw, values) do
      #   Enum.zip(unquote(field_names), values)
      # end

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

  @types [ :string, :integer, :float, :binary, :list, :virtual ]

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
    # TODO: Check that the opts are valid for the given type

    quote do
      field_name = unquote(name)
      type = unquote(type)
      opts = unquote(opts)
      Ecto.Entity.Dataset.check_type(type)

      clash = Enum.any?(@ecto_fields, fn({ prev_name, _ }) -> field_name == prev_name end)
      if clash do
        raise ArgumentError, message: "field `#{field_name}` was already set on entity"
      end

      if opts[:primary_key] do
        if @ecto_primary_key do
          message = "there can only be one primary key, a custom primary key " <>
            "requires the default to be disabled, see `Ecto.Entity.dataset`"
          raise ArgumentError, message: message
        end
        @ecto_primary_key field_name
      end

      default = opts[:default]
      @ecto_fields { field_name, [type: type] ++ opts }
    end
  end

  defmacro has_many(name, entity, opts // []) do
    quote do
      name = unquote(name)
      assoc = Ecto.Associations.HasMany[__name__: name]
      field(:"__#{name}__", :virtual, default: assoc)
      @ecto_assocs { name, [entity: unquote(entity)] ++ unquote(opts) }
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
