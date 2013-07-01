defmodule Ecto.Entity do
  defmacro __using__(_opts) do
    quote do
      import Ecto.Entity.DSL

      @on_definition unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :ecto_defs, accumulate: false, persist: false)
      Module.register_attribute(__MODULE__, :ecto_table_name, accumulate: false, persist: false)
      Module.register_attribute(__MODULE__, :ecto_fields, accumulate: true, persist: false)
      Module.register_attribute(__MODULE__, :ecto_record_fields, accumulate: true, persist: false)
    end
  end

  defmacro __before_compile__(env) do
    module        = env.module
    table_name    = Module.get_attribute(module, :ecto_table_name)
    fields        = Module.get_attribute(module, :ecto_fields) |> Enum.reverse
    record_fields = Module.get_attribute(module, :ecto_record_fields) |> Enum.reverse

    unless table_name do
      raise ArgumentError, message: "no support for dasherize and pluralize yet, " <>
                                    "a table name is required"
    end

    Record.deffunctions(record_fields, env)

    fields_quote = Enum.map(fields, fn({ key, value }) ->
      quote do
        def __ecto__(:fields, unquote(key)), do: unquote(value)
      end
    end)

    quote do
      def __ecto__(:table), do: unquote(table_name)
      def __ecto__(:fields), do: unquote(Macro.escape(fields))
      unquote_splicing(fields_quote)
    end
  end

  def __on_definition__(env, _kind, _name, _args, _guards, _body) do
    Module.put_attribute(env.module, :ecto_defs, true)
  end
end

defmodule Ecto.Entity.DSL do
  defmacro table_name(name) do
    check_defs(__CALLER__)
    quote do
      @ecto_table_name unquote(name)
    end
  end

  defmacro primary_key(name // :id) do
    quote do
      field(unquote(name), :integer, primary_key: true, autoinc: true, uniq: true)
    end
  end

  defmacro field(name, type, opts) do
    check_defs(__CALLER__)
    quote do
      opts = unquote(opts)
      default = opts[:default]
      @ecto_record_fields { unquote(name), default }
      @ecto_fields { unquote(name), [type: unquote(type)] ++ opts }
    end
  end

  def check_defs(env) do
    if Module.get_attribute(env.module, :ecto_defs) do
      raise ArgumentError, message: "Entity needs to be defined before any function " <>
                                    "or macro definitions"
    end
  end
end
