defmodule Ecto.Query.Typespec do
  @doc """
  A very simple type system to declare the operators and functions
  available in Ecto with their types. At runtime, the type system
  does no inference, it simply maps input types to output types.
  """

  @doc """
  Defines a new Ecto.Query type.
  """
  defmacro deft(expr) do
    name = extract_type(expr)
    quote do
      @ecto_deft [unquote(name)|@ecto_deft]
      def unquote(name)(), do: unquote(name)
    end
  end

  @doc """
  Defines a new Ecto.Query alias.

  Aliases are only used by the type system, they are not
  exposed to the user.
  """
  defmacro defa({ :::, _, [_, _] } = expr) do
    quote bind_quoted: [expr: Macro.escape(expr)] do
      { left, right } = Ecto.Query.Typespec.__defa__(__MODULE__, expr)
      @ecto_defa Dict.put(@ecto_defa, left, right)
    end
  end

  @doc """
  Defines a new Ecto.Query spec.
  """
  defmacro defs({ :::, _, [head, _] } = expr) do
    quote bind_quoted: [expr: Macro.escape(expr), head: Macro.escape(head)] do
      { name, args, guards, return, catch_all } = Ecto.Query.Typespec.__defs__(__MODULE__, expr)
      arity = length(args)

      if @aggregate do
        @ecto_aggregates [{ name, arity }|@ecto_aggregates]
      end
      @aggregate false

      if catch_all do
        @ecto_defs Dict.delete(@ecto_defs, { name, arity })
      else
        @ecto_defs Dict.update(@ecto_defs, { name, arity }, [head], &[head|&1])
      end
      def unquote(name)(unquote_splicing(args)) when unquote(guards), do: { :ok, unquote(return) }
    end
  end

  ## Callbacks

  @doc false
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      @ecto_aggregates []
      @ecto_deft []
      @ecto_defs HashDict.new
      @ecto_defa HashDict.new
      @aggregate false
    end
  end

  @doc false
  def __defs__(mod, { :::, meta, [left, right] })  do
    { name, args } = Macro.extract_args(left)

    deft = Module.get_attribute(mod, :ecto_deft)
    defa = Module.get_attribute(mod, :ecto_defa)

    var_types =
      Enum.map(Stream.with_index(args), fn
        { { :^, _, [var] }, _index } ->
          { var, nil }
        { arg, index } ->
          types = arg |> extract_types([]) |> expand_types(deft, defa)
          { { :"x#{index}", meta, __MODULE__ }, types }
      end)

    right = case right do
      { :^, _, [var] } -> var
      _ -> extract_type(right)
    end

    catch_all = Enum.all?(var_types, &match?({ _, nil }, &1)) and
                Enum.uniq(var_types) == var_types

    { name, Dict.keys(var_types), compile_guards(var_types), right, catch_all }
  end

  @doc false
  def __defa__(mod, { :::, _, [left, right] }) do
    deft = Module.get_attribute(mod, :ecto_deft)
    defa = Module.get_attribute(mod, :ecto_defa)
    { extract_type(left), right |> extract_types([]) |> expand_types(deft, defa) }
  end

  @doc false
  def __args__(arity) do
    tl(Enum.to_list(0..arity)) |> Enum.map(fn(i) -> { :"x#{i}", [], __MODULE__ } end)
  end

  @doc false
  defmacro __before_compile__(env) do
    defs = Module.get_attribute(env.module, :ecto_defs)
    aggregates = Module.get_attribute(env.module, :ecto_aggregates)

    defs_quote = Enum.map(defs, fn { { name, arity }, exprs } ->
      args  = Stream.repeatedly(fn -> { :_, [], __MODULE__ } end) |> Enum.take(arity)
      exprs = Macro.escape(Enum.reverse(exprs))

      quote do
        def unquote(name)(unquote_splicing(args)) do
          { :error, unquote(exprs) }
        end
      end
    end)

    aggregates_quote = Enum.map(aggregates, fn({ name, arity }) ->
      quote do
        def aggregate?(unquote(name), unquote(arity)), do: true
      end
    end) ++ [quote do def aggregate?(_, _), do: false end]

    defs_quote ++ aggregates_quote
  end

  ## Helpers

  defp extract_type({ name, _, context }) when is_atom(name) and is_atom(context) do
    name
  end

  defp extract_type(name) when is_atom(name) do
    name
  end

  defp extract_type(expr) do
    raise "invalid type expression: #{Macro.to_string(expr)}"
  end

  defp extract_types({ :|, _, [left, right ] }, acc) do
    extract_types(left, extract_types(right, acc))
  end

  defp extract_types(other, acc) do
    [extract_type(other)|acc]
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
    guards = lc { var, types } inlist var_types, types != nil, do: { var, types }

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

  defp compile_guard({ var, types }) do
    quote do: unquote(var) in unquote(types)
  end
end
