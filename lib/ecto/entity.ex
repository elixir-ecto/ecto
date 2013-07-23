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
        @ecto_primary_key primary_key

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
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    module        = env.module
    dataset_name  = Module.get_attribute(module, :ecto_dataset)
    primary_key   = Module.get_attribute(module, :ecto_primary_key)
    fields        = Module.get_attribute(module, :ecto_fields) |> Enum.reverse
    field_names   = Enum.map(fields, elem(&1, 0))

    unless dataset_name do
      raise ArgumentError, message: "dataset not defined, an entity has " <>
        "define a dataset, see `Ecto.Entity.Dataset`"
    end

    fields_quote = Enum.map(fields, fn({ key, opts }) ->
      quote do
        def __ecto__(:field, unquote(key)), do: unquote(opts)
        def __ecto__(:field_type, unquote(key)), do: unquote(opts[:type])
      end
    end)

    quote do
      def __ecto__(:dataset), do: unquote(dataset_name)
      def __ecto__(:primary_key), do: unquote(primary_key)
      def __ecto__(:fields), do: unquote(Macro.escape(fields))
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
    end
  end

  # Check if an expression is an entity
  @doc false
  def is_entity(entity) do
    is_atom(entity) and
     Code.ensure_compiled?(entity) and
     function_exported?(entity, :__ecto__, 1)
  end
end

defmodule Ecto.Entity.Dataset do
  @moduledoc """
  This module contains all macros used to define the dataset for an entity.
  """

  @types [ :string, :integer, :float, :binary ]

  @doc """
  Defines a field on the entity with given name and type, will also create a
  record field.

  ## Options

    * `:default` - Sets the default value on the entity and the record
  """
  defmacro field(name, type, opts // []) do
    # TODO: Check that the opts are valid for the given type

    quote do
      name = unquote(name)
      type = unquote(type)

      clash = Enum.any?(@ecto_fields, fn({ prev_name, _ }) -> name == prev_name end)
      if clash do
        raise ArgumentError, message: "field `#{name}` was already set on entity"
      end

      unless type in unquote(@types) do
        raise ArgumentError, message: "`#{type}` is not a valid field type"
      end

      opts = unquote(opts)
      default = opts[:default]
      @ecto_fields { name, [type: type] ++ opts }
    end
  end
end
