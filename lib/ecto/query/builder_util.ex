defmodule Ecto.Query.BuilderUtil do
  @moduledoc false

  alias Ecto.Query

  @expand_sigils [:sigil_c, :sigil_C, :sigil_s, :sigil_S, :sigil_w, :sigil_W]

  @doc """
  Smart escapes a query expression.

  Everything that is a query expression will be escaped, foreign (elixir)
  expressions will not be escaped so that they will be evaluated in their
  place. This means that everything foreign will be inserted as-is into
  the query.
  """
  @spec escape(Macro.t, Keyword.t) :: Macro.t
  def escape(expr, vars)

  # var.x - where var is bound
  def escape({{:., _, [{var, _, context}, right]}, _, []}, vars)
      when is_atom(var) and is_atom(context) and is_atom(right) do
    left_escaped = escape_var(var, vars)
    dot_escaped = {:{}, [], [:., [], [left_escaped, right]]}
    {:{}, [], [dot_escaped, [], []]}
  end

  # interpolation
  def escape({:^, _, [arg]}, _vars) do
    arg
  end

  # ecto types
  def escape({:binary, _, [arg]}, vars) do
    arg_escaped = escape(arg, vars)
    {:%, [], [Ecto.Binary, {:%{}, [], [value: arg_escaped]}]}
  end

  def escape({:array, _, [arg, type]}, vars) do
    arg  = escape(arg, vars)
    type = escape(type, vars)
    type = quote(do: :"Elixir.Ecto.Query.BuilderUtil".check_array(unquote(type)))
    {:%, [], [Ecto.Array, {:%{}, [], [value: arg, type: type]}]}
    # TODO: Check that arg is and type is an atom
  end

  # field macro
  def escape({:field, _, [{var, _, context}, field]}, vars)
      when is_atom(var) and is_atom(context) do
    var   = escape_var(var, vars)
    field = escape(field, vars)
    field = quote(do: :"Elixir.Ecto.Query.BuilderUtil".check_field(unquote(field)))
    dot   = {:{}, [], [:., [], [var, field]]}
    {:{}, [], [dot, [], []]}
  end

  # binary literal
  def escape({:<<>>, _, _} = bin, _vars), do: bin

  # sigils
  def escape({name, _, _} = sigil, _vars) when name in @expand_sigils do
    sigil
  end

  # ops & functions
  def escape({name, meta, args}, vars) when is_atom(name) and is_list(args) do
    args = Enum.map(args, &escape(&1, vars))
    {:{}, [], [name, meta, args]}
  end

  # list
  def escape(list, vars) when is_list(list) do
    Enum.map(list, &escape(&1, vars))
  end

  # literals
  def escape(literal, _vars) when is_binary(literal), do: literal
  def escape(literal, _vars) when is_boolean(literal), do: literal
  def escape(literal, _vars) when is_number(literal), do: literal
  def escape(nil, _vars), do: nil

  # everything else is not allowed
  def escape(other, _vars) do
    raise Ecto.QueryError, reason: "`#{Macro.to_string(other)}` is not a valid query expression"
  end

  @doc """
  Escapes a variable according to the given binds.

  A escaped variable is represented internally as `&0`, `&1` and
  so on. This function is also responsible for handling join vars
  which use a `count_binds` variable assigned to the `Ecto.Query`
  to pass the required index information.
  """
  @spec escape_var(atom, Keyword.t) :: Macro.t | no_return
  def escape_var(var, vars)

  def escape_var(var, vars) do
    ix = vars[var]

    if var != :_ and ix do
      {:{}, [], [:&, [], [ix]]}
    else
      raise Ecto.QueryError, reason: "unbound variable `#{var}` in query"
    end
  end

  @doc """
  Escapes dot calls in query expressions.

  A dot may be in three formats, all shown in the examples below.
  Returns :error if it isn't a dot expression.

  ## Examples

      iex> escape_dot(quote(do: x.y), [x: 0])
      {{:{}, [], [:&, [], [0]]}, :y}

      iex> escape_dot(quote(do: x.y()), [x: 0])
      {{:{}, [], [:&, [], [0]]}, :y}

      iex> escape_dot(quote(do: field(x, ^:y)), [x: 0])
      {{:{}, [], [:&, [], [0]]},
        {{:., [], [:"Elixir.Ecto.Query.BuilderUtil", :check_field]}, [], [:y]}}

      iex> escape_dot(quote(do: x), [x: 0])
      :error

  """
  @spec escape_dot(Macro.t, Keyword.t) :: {Macro.t, Macro.t} | :error
  def escape_dot({:field, _, [{var, _, context}, field]}, vars)
      when is_atom(var) and is_atom(context) do
    var   = escape_var(var, vars)
    field = escape(field, vars)
    field = quote(do: :"Elixir.Ecto.Query.BuilderUtil".check_field(unquote(field)))
    {var, field}
  end

  def escape_dot({{:., _, [{var, _, context}, field]}, _, []}, vars)
      when is_atom(var) and is_atom(context) and is_atom(field) do
    {escape_var(var, vars), field}
  end

  def escape_dot(_, _vars) do
    :error
  end

  @doc """
  Escapes a list of bindings as a list of atoms.

  ## Examples

      iex> escape_binding(quote do: [x, y, z])
      [x: 0, y: 1, z: 2]

      iex> escape_binding(quote do: [x, y, x])
      ** (Ecto.QueryError) variable `x` is bound twice

  """
  def escape_binding(binding) when is_list(binding) do
    vars       = binding |> Stream.with_index |> Enum.map(&escape_bind(&1))
    bound_vars = vars |> Keyword.keys |> Enum.filter(&(&1 != :_))
    dup_vars   = bound_vars -- Enum.uniq(bound_vars)

    unless dup_vars == [] do
      raise Ecto.QueryError, reason: "variable `#{hd dup_vars}` is bound twice"
    end

    vars
  end

  def escape_binding(bind) do
    raise Ecto.QueryError, reason: "binding should be list of variables, got: #{Macro.to_string(bind)}"
  end

  defp escape_bind({{var, _} = tuple, _}) when is_atom(var),
    do: tuple
  defp escape_bind({{var, _, context}, ix}) when is_atom(var) and is_atom(context),
    do: {var, ix}
  defp escape_bind({bind, _ix}),
    do: raise(Ecto.QueryError, reason: "binding list should contain only variables, got: #{Macro.to_string(bind)}")


  @doc """
  Escapes simple expressions.

  An expression may be a single variable `x`, representing all fields in that
  model, a field `x.y`, or a list of fields and variables.

  ## Examples

      iex> escape_fields_and_vars(quote(do: [x.x, y.y]), [x: 0, y: 1])
      [{{:{}, [], [:&, [], [0]]}, :x},
       {{:{}, [], [:&, [], [1]]}, :y}]

      iex> escape_fields_and_vars(quote(do: x), [x: 0, y: 1])
      [{:{}, [], [:&, [], [0]]}]

  """
  @spec escape_fields_and_vars(Macro.t, Keyword.t) :: Macro.t | no_return
  def escape_fields_and_vars(ast, vars) do
    Enum.map(List.wrap(ast), &do_escape_expr(&1, vars))
  end

  defp do_escape_expr({var, _, context}, vars) when is_atom(var) and is_atom(context) do
    escape_var(var, vars)
  end

  defp do_escape_expr(dot, vars) do
    case escape_dot(dot, vars) do
      {_, _} = var_field ->
        var_field
      :error ->
        raise Ecto.QueryError, reason: "malformed query expression"
    end
  end

  @doc """
  Counts the bindings in a query expression.

  ## Examples

      iex> count_binds(%Ecto.Query{joins: [1,2,3]})
      3

      iex> count_binds(%Ecto.Query{from: 0, joins: [1,2]})
      3

  """
  def count_binds(%Query{from: from, joins: joins}) do
    count = if from, do: 1, else: 0
    count + length(joins)
  end

  @doc """
  Applies a query at compilation time or at runtime.

  This function is responsible to check if a given query is an
  `Ecto.Query` struct at compile time or not and act accordingly.

  If a query is available, it invokes the `apply` function in the
  given `module`, otherwise, it delegates the call to runtime.

  It is important to keep in mind the complexities introduced
  by this function. In particular, a %Query{} is mixture of escaped
  and unescaped expressions which makes it impossible for this
  function to properly escape or unescape it at compile/runtime.
  For this reason, the apply function should be ready to handle
  arguments in both escaped and unescaped form.

  For example, take into account the `SelectBuilder`:

      select = %Ecto.Query.QueryExpr{expr: expr, file: env.file, line: env.line}
      BuilderUtil.apply_query(query, __MODULE__, [select], env)

  `expr` is already an escaped expression and we must not escape
  it again. However, it is wrapped in an Ecto.Query.QueryExpr,
  which must be escaped! Furthermore, the `apply/2` function
  in `SelectBuilder` very likely will inject the QueryExpr inside
  Query, which again, is a mixture of escaped and unescaped expressions.

  That said, you need to obey the following rules:

  1. In order to call this function, the arguments must be escapable
     values supported by the `escape/1` function below;

  2. The apply function may not manipulate the given arguments,
     with exception to the query.

  In particular, when invoked at compilation time, all arguments
  (except the query) will be escaped, so they can be injected into
  the query properly, but they will be in their runtime form
  when invoked at runtime.
  """
  def apply_query(query, module, args, env) do
    query = Macro.expand(query, env)
    args  = for i <- args, do: escape_query(i)
    case unescape_query(query) do
      %Query{} = unescaped ->
        apply(module, :apply, [unescaped|args]) |> escape_query
      _ ->
        quote do: unquote(module).apply(unquote_splicing([query|args]))
    end
  end

  # Unescapes an `Ecto.Query` struct.
  defp unescape_query({:%, _, [Query, {:%{}, _, list}]}) do
    struct(Query, list)
  end

  defp unescape_query({:%{}, _, list} = ast) do
    if List.keyfind(list, :__struct__, 0) == {:__struct__, Query} do
      Enum.into(list, %{})
    else
      ast
    end
  end

  defp unescape_query(other) do
    other
  end

  # Escapes an `Ecto.Query` and associated structs.
  defp escape_query(%Query{} = query),
    do: {:%{}, [], Map.to_list(query)}
  defp escape_query(other),
    do: other

  @doc """
  Called by escaper at runtime to verify that `field/2` is given an atom.
  """
  def check_field(field) do
    if is_atom(field) do
      field
    else
      raise Ecto.QueryError, reason: "field name should be an atom, given: `#{inspect field}`"
    end
  end

  @doc """
  Called by escaper at runtime to verify that `array/2` is given an atom.
  """
  def check_array(type) do
    if is_atom(type) do
      type
    else
      raise Ecto.QueryError, reason: "array type should be an atom, given: `#{inspect type}`"
    end
  end
end
