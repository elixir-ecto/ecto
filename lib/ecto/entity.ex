defmodule Ecto.Entity do
  @moduledoc """
  This module is used to define an entity. An entity is a record with associated
  meta data that will be used when creating and running queries. See
  `Ecto.Entity.Schema` for more information about the specific functions used to
  specify an entity.

  Every entity is also a record, that means that you work with entities just
  like you would work with records, to set the default values for the record
  fields the `default` option is set in the `field` options.

  ## Example
      defmodule User do
        use Ecto.Entity

        schema :users do
          field :name, :string
          field :age, :integer
        end
      end
  """

  @doc """
  Defines the entity schema. Takes an optional primary key name, if none is
  given, defaults to `:id`, pass `nil` if there should be no primary key.
  """
  defmacro schema(table, primary_key // :id, block) do
    quote do
      primary_key = unquote(primary_key)

      if Module.get_attribute(__MODULE__, :ecto_defs) do
        message = "schema needs to be defined before any function " <>
                  "or macro definitions"
        raise ArgumentError, message: message
      end

      try do
        import Ecto.Entity.Schema
        @ecto_table_name unquote(table)
        @primary_key unquote(primary_key)
        if primary_key do
          field(unquote(primary_key), :integer, primary_key: true)
        end
        unquote(block)
      end
    end
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Ecto.Entity, only: [schema: 2, schema: 3]

      @on_definition unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :ecto_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :record_fields, accumulate: true)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    module        = env.module
    table_name    = Module.get_attribute(module, :ecto_table_name)
    primary_key   = Module.get_attribute(module, :primary_key)
    fields        = Module.get_attribute(module, :ecto_fields) |> Enum.reverse
    record_fields = Module.get_attribute(module, :record_fields) |> Enum.reverse
    field_names   = Enum.map(fields, elem(&1, 0))

    unless table_name do
      raise ArgumentError, message: "no support for dasherize or pluralize yet, " <>
                                    "a table name is required"
    end

    Record.deffunctions(record_fields, env)

    fields_quote = Enum.map(fields, fn({ key, opts }) ->
      quote do
        opts = unquote(opts)
        def __ecto__(:field, unquote(key)), do: unquote(opts)
        def __ecto__(:field_type, unquote(key)), do: unquote(opts[:type])
      end
    end)

    quote do
      def __ecto__(:table), do: unquote(table_name)
      def __ecto__(:primary_key), do: unquote(primary_key)
      def __ecto__(:fields), do: unquote(Macro.escape(fields))
      def __ecto__(:field_names), do: unquote(field_names)
      unquote(fields_quote)
      def __ecto__(:field, _), do: nil
      def __ecto__(:field_type, _), do: nil
    end
  end

  @doc false
  def __on_definition__(env, _kind, _name, _args, _guards, _body) do
    Module.put_attribute(env.module, :ecto_defs, true)
  end
end

defmodule Ecto.Entity.Schema do
  @moduledoc """
  This module contains all macros used to define the schema for an entity.
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
      @record_fields { name, default }
      @ecto_fields { name, [type: type] ++ opts }
    end
  end
end
