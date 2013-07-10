defmodule Ecto.Entity do
  @moduledoc """
  This module is used to define an entity. An entity is a record with associated
  meta data that will be used when creating and running queries. See
  `Ecto.Entity.DSL` for more information about the specific functions used to
  specify an entity.

  Every entity is also a record, that means that you work with entities just
  like you would work with records, to set the default values for the record
  fields the `default` option is set in the `field` options.

  ## Example
      defmodule User do
        use Ecto.Entity
        table_name :users

        primary_key
        field :name, :string
        field :age, :integer
      end
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Ecto.Entity.DSL

      @on_definition unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      @ecto_primary_key false
      Module.register_attribute(__MODULE__, :ecto_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :record_fields, accumulate: true)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    module        = env.module
    table_name    = Module.get_attribute(module, :ecto_table_name)
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

defmodule Ecto.Entity.DSL do
  @moduledoc """
  This module contains all macros used to define an entity.
  """

  @types [ :string, :integer, :float, :binary ]

  @doc """
  Sets the entities table name. Can be an atom or a string.
  """
  defmacro table_name(name) when is_atom(name) or is_binary(name) do
    check_defs(__CALLER__)
    quote do
      @ecto_table_name unquote(name)
    end
  end

  @doc """
  Defines a primary key field of type integer. Only one primary key can be
  defined. The default name is id.
  """
  defmacro primary_key(name // :id) do
    quote do
      if @ecto_primary_key do
        raise ArgumentError, message: "only one primary key can be set on an entity"
      end

      @ecto_primary_key true
      field(unquote(name), :integer, primary_key: true)
    end
  end

  @doc """
  Defines a field on the entity with given name and type, will also create a
  record field.

  ## Options

    * `:default` - Sets the default value on the entity and the record
  """
  defmacro field(name, type, opts // []) do
    # TODO: Check that the opts are valid for the given type
    check_defs(__CALLER__)
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

  defp check_defs(env) do
    if Module.get_attribute(env.module, :ecto_defs) do
      raise ArgumentError, message: "entity needs to be defined before any function " <>
                                    "or macro definitions"
    end
  end
end
