defmodule Ecto.Query.Typespec do
  @moduledoc false

  # A very simple type system to declare the operators and functions
  # available in Ecto with their types. At runtime, the type system
  # does no inference, it simply maps input types to output types.

  @doc """
  Defines a new Ecto.Query type.
  """
  defmacro deft(expr) do
    name = extract_type(expr)
    quote do
      @ecto_deft [unquote(name)|@ecto_deft]
    end
  end

  @doc """
  Defines a new Ecto.Query alias.

  Aliases are only used by the type system, they are not
  exposed to the user.
  """
  defmacro defa({:::, _, [_, _]} = expr) do
    quote bind_quoted: [expr: Macro.escape(expr)] do
      {left, right} = Ecto.Query.Typespec.__defa__(__MODULE__, expr)
      @ecto_defa Dict.put(@ecto_defa, left, right)
    end
  end

  @doc """
  Defines a new Ecto.Query spec.
  """
  defmacro defs({:::, _, [head, _]} = expr) do
    quote bind_quoted: [expr: Macro.escape(expr), head: Macro.escape(head)] do
      var!(defs, Ecto.Query.Typespec).(expr, head)
    end
  end

  ## Callbacks

  defmacro __using__(_) do
    quote unquote: false do
      import Ecto.Query.Typespec
      @before_compile Ecto.Query.Typespec
      @ecto_deft []
      @ecto_defs HashDict.new
      @ecto_defa HashDict.new
      @aggregate false

      # Instead of injecting this code multiple times into the user module,
      # we simply define this function at the beginning and invoke it. This
      # reduces the memory consumption when compiling Ecto.Query.API from
      # 270MB to 70MB.
      var!(defs, Ecto.Query.Typespec) = fn expr, head ->
        {name, args, guards, return, catch_all} = Ecto.Query.Typespec.__defs__(__MODULE__, expr)
        arity = length(args)

        if @aggregate do
          @doc false
          def aggregate?(unquote(name), unquote(arity)), do: true
        end
        @aggregate false

        if catch_all do
          @ecto_defs Dict.delete(@ecto_defs, {name, arity})
        else
          @ecto_defs Dict.update(@ecto_defs, {name, arity}, [head], &[head|&1])
        end

        def unquote(name)(unquote_splicing(args)) when unquote(guards), do: {:ok, unquote(return)}
      end
    end
  end

  def __defs__(mod, {:::, meta, [left, right]})  do
    {name, args} = Macro.decompose_call(left)

    deft = Module.get_attribute(mod, :ecto_deft)
    defa = Module.get_attribute(mod, :ecto_defa)
    meta = {meta, deft, defa}

    {args, var_types} =
      Enum.reduce(Stream.with_index(args), {[], []}, fn
        {{arg, _, [inner]}, index}, {args, types} ->
          {var1, var_types} = var_types(arg, index, "x", meta)
          types = types ++ [{var1, var_types}]
          {var2, var_types} = var_types(inner, index, "y", meta)
          arg = {var1, var2}
          {args ++ [arg], types ++ [{var2, var_types}]}

        {arg, index}, {args, types} ->
          {var, var_types} = var_types(arg, index, "x", meta)
          {args ++ [var], types ++ [{var, var_types}]}
      end)

    right = extract_return_type(right)

    catch_all = Enum.all?(var_types, &match?({_, nil}, &1)) and
                Enum.uniq(var_types) == var_types

    {name, args, compile_guards(var_types), right, catch_all}
  end

  def __defa__(mod, {:::, _, [left, right]}) do
    deft = Module.get_attribute(mod, :ecto_deft)
    defa = Module.get_attribute(mod, :ecto_defa)
    {extract_type(left), right |> extract_types([]) |> expand_types(deft, defa)}
  end

  defmacro __before_compile__(env) do
    defs = Module.get_attribute(env.module, :ecto_defs)

    defs_quote = Enum.map(defs, fn {{name, arity}, exprs} ->
      args  = Stream.repeatedly(fn -> {:_, [], __MODULE__} end) |> Enum.take(arity)
      exprs = Macro.escape(Enum.reverse(exprs))

      quote do
        def unquote(name)(unquote_splicing(args)) do
          {:error, unquote(exprs)}
        end
      end
    end)

    defs_quote ++ [quote do def aggregate?(_, _), do: false end]
  end

  ## Helpers

  defp var_types({:var, _, nil} = var, _index, _prefix, _meta) do
    {var, nil}
  end

  defp var_types({:_, _, nil}, index, prefix, {meta, _, _}) do
    {{:"#{prefix}#{index}", meta, __MODULE__}, nil}
  end

  defp var_types(arg, index, prefix, {meta, deft, defa}) do
    types = arg |> extract_types([]) |> expand_types(deft, defa)
    {{:"#{prefix}#{index}", meta, __MODULE__}, types}
  end

  defp extract_type({name, _, [_]}) when is_atom(name) do
    name
  end

  defp extract_type({name, _, context}) when is_atom(name) and is_atom(context) do
    name
  end

  defp extract_type(name) when is_atom(name) do
    name
  end

  defp extract_type(expr) do
    raise "invalid type expression: #{Macro.to_string(expr)}"
  end

  defp extract_types({:|, _, [left, right ]}, acc) do
    extract_types(left, extract_types(right, acc))
  end

  defp extract_types(other, acc) do
    [extract_type(other)|acc]
  end

  defp extract_return_type({name, _, [{:var, _, nil} = var]}) when is_atom(name) do
    {name, var}
  end

  defp extract_return_type({name, _, [{var, _, nil}]}) when is_atom(name) and is_atom(var) do
    {name, var}
  end

  defp extract_return_type({:var, _, nil} = var) do
    var
  end

  defp extract_return_type({name, _, context}) when is_atom(name) and is_atom(context) do
    name
  end

  defp extract_return_type(name) when is_atom(name) do
    name
  end

  defp extract_return_type(expr) do
    raise "invalid type expression: #{Macro.to_string(expr)}"
  end

  defp expand_types(types, deft, defa) do
    Enum.reduce types, [], fn type, acc ->
      cond do
        type in deft ->
          [type|acc]
        aliases = defa[type] ->
          aliases ++ acc
        true ->
          raise "unknown type or alias #{type}"
      end
    end
  end

  defp compile_guards(var_types) do
    guards = Enum.filter(var_types, fn({_, types}) -> types != nil end)

    case guards do
      []    -> true
      [h|t] ->
        Enum.reduce t, compile_guard(h), fn tuple, acc ->
          quote do
            unquote(compile_guard(tuple)) and unquote(acc)
          end
        end
    end
  end

  defp compile_guard({var, types}) do
    quote do: unquote(var) in unquote(types) or unquote(var) == :any
  end
end
