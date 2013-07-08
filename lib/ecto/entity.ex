defmodule Ecto.Entity do
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

  defmacro __before_compile__(env) do
    module        = env.module
    table_name    = Module.get_attribute(module, :ecto_table_name)
    fields        = Module.get_attribute(module, :ecto_fields) |> Enum.reverse
    record_fields = Module.get_attribute(module, :record_fields) |> Enum.reverse
    field_names   = Enum.map(fields, elem(&1, 0))

    unless table_name do
      raise ArgumentError, message: "no support for dasherize and pluralize yet, " <>
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

  def __on_definition__(env, _kind, _name, _args, _guards, _body) do
    Module.put_attribute(env.module, :ecto_defs, true)
  end
end

defmodule Ecto.Entity.DSL do
  @types [ :string, :integer, :float, :binary ]

  defmacro table_name(name) do
    check_defs(__CALLER__)
    quote do
      @ecto_table_name unquote(name)
    end
  end

  defmacro primary_key(name // :id) do
    quote do
      if @ecto_primary_key do
        raise ArgumentError, message: "only one primary key can be set on an entity"
      end

      @ecto_primary_key true
      field(unquote(name), :integer, primary_key: true)
    end
  end

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

  def check_defs(env) do
    if Module.get_attribute(env.module, :ecto_defs) do
      raise ArgumentError, message: "entity needs to be defined before any function " <>
                                    "or macro definitions"
    end
  end
end
