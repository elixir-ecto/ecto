defmodule Ecto.Query.BuilderUtil do
  @moduledoc false

  alias Ecto.Query.Query

  @doc """
  Smart escapes a query expression.

  Everything that is a query expression will be escaped, foreign (elixir)
  expressions will not be escaped so that they will be evaluated in their
  place. This means that everything foreign will be inserted as-is into
  the query.
  """
  @spec escape(Macro.t, [atom], { atom, Macro.t } | nil) :: Macro.t
  def escape(expr, vars, join_var // nil)

  # var.x - where var is bound
  def escape({ { :., _, [{ var, _, context}, right] }, _, [] }, vars, join_var)
      when is_atom(var) and is_atom(context) and is_atom(right) do
    left_escaped = escape_var(var, vars, join_var)
    dot_escaped = { :{}, [], [:., [], [left_escaped, right]] }
    { :{}, [], [dot_escaped, [], []] }
  end

  # interpolation
  def escape({ :^, _, [arg] }, _vars, _join_var) do
    arg
  end

  # ecto types
  def escape({ :binary, _, [arg] }, vars, join_var) do
    arg_escaped = escape(arg, vars, join_var)
    Ecto.Binary[value: arg_escaped]
  end

  # field macro
  def escape({ :field, _, [{ var, _, context }, field] }, vars, join_var)
      when is_atom(var) and is_atom(context) do
    var   = escape_var(var, vars, join_var)
    field = escape(field, vars, join_var)
    dot   = { :{}, [], [:., [], [var, field]] }
    { :{}, [], [dot, [], []] }
  end

  # binary literal
  def escape({ :<<>>, _, _ } = bin, _vars, _join_var), do: bin

  # ops & functions
  def escape({ name, meta, args }, vars, join_var)
      when is_atom(name) and is_list(args) do
    args = Enum.map(args, &escape(&1, vars, join_var))
    { :{}, [], [name, meta, args] }
  end

  # list
  def escape(list, vars, join_var) when is_list(list) do
    Enum.map(list, &escape(&1, vars, join_var))
  end

  # literals
  def escape(literal, _vars, _join_var) when is_binary(literal), do: literal
  def escape(literal, _vars, _join_var) when is_boolean(literal), do: literal
  def escape(literal, _vars, _join_var) when is_number(literal), do: literal
  def escape(nil, _vars, _join_var), do: nil

  # everything else is not allowed
  def escape(other, _vars, _join_var) do
    raise Ecto.QueryError, reason: "`#{Macro.to_string(other)}` is not a valid query expression"
  end

  @doc """
  Escapes a variable according to the given binds.

  A escaped variable is represented internally as `&0`, `&1` and
  so on. This function is also responsible for handling join vars
  which use a `count_binds` variable assigned to the `Ecto.Query`
  to pass the required indice information.
  """
  @spec escape_var(atom, [atom], { atom, Macro.t } | nil) :: Macro.t | no_return
  def escape_var(var, vars, join_var // nil)

  def escape_var(var, _vars, { var, idx }) do
    { :{}, [], [:&, [], [idx]] }
  end

  def escape_var(var, vars, _join_var) do
    ix = Enum.find_index(vars, &(&1 == var))

    if var != :_ and ix do
      { :{}, [], [:&, [], [ix]] }
    else
      raise Ecto.QueryError, reason: "unbound variable `#{var}` in query"
    end
  end

  @doc """
  Escapes dot calls in query expressions.

  A dot may be in three formats, all shown in the examples below.
  Returns :error if it isn't a dot expression.

  ## Examples

      iex> escape_dot(quote(do: x.y), [:x])
      {{:{}, [], [:&, [], [0]]}, :y}

      iex> escape_dot(quote(do: x.y()), [:x])
      {{:{}, [], [:&, [], [0]]}, :y}

      iex> escape_dot(quote(do: field(x, ^:y)), [:x])
      {{:{}, [], [:&, [], [0]]}, :y}

      iex> escape_dot(quote(do: x), [:x])
      :error

  """
  @spec escape_dot(Macro.t, [atom]) :: { Macro.t, Macro.t } | :error
  def escape_dot({ :field, _, [{ var, _, context }, field] }, vars)
      when is_atom(var) and is_atom(context) do
    { escape_var(var, vars), escape(field, vars) }
  end

  def escape_dot({ { :., _, [{ var, _, context }, field] }, _, [] }, vars)
      when is_atom(var) and is_atom(context) and is_atom(field) do
    { escape_var(var, vars), field }
  end

  def escape_dot(_, _vars) do
    :error
  end

  @doc """
  Escapes a list of bindings as a list of atoms.

  ## Examples

      iex> escape_binding(quote do: [x, y, z])
      [:x, :y, :z]

      iex> escape_binding(quote do: [x, y, x])
      ** (Ecto.QueryError) variable `x` is bound twice

  """
  def escape_binding(binding) when is_list(binding) do
    vars       = Enum.map(binding, &escape_bind(&1))
    bound_vars = Enum.filter(vars, &(&1 != :_))
    dup_vars   = bound_vars -- Enum.uniq(bound_vars)

    unless dup_vars == [] do
      raise Ecto.QueryError, reason: "variable `#{hd dup_vars}` is bound twice"
    end

    vars
  end

  def escape_binding(bind) do
    raise Ecto.QueryError, reason: "binding should be list of variables, got: #{Macro.to_string(bind)}"
  end

  defp escape_bind(var) when is_atom(var),
    do: var
  defp escape_bind({ var, _, context }) when is_atom(var) and is_atom(context),
    do: var
  defp escape_bind(bind),
    do: raise(Ecto.QueryError, reason: "binding list should contain only variables, got: #{Macro.to_string(bind)}")

  @doc """
  Counts the bindings in a query expression.

  ## Examples

      iex> count_binds(Ecto.Query.Query[joins: [1,2,3]])
      3

      iex> count_binds(Ecto.Query.Query[from: 0, joins: [1,2]])
      3

  """
  def count_binds(Query[from: from, joins: joins]) do
    count = if from, do: 1, else: 0
    count + length(joins)
  end

  @doc """
  Applies a query at compilation time or at runtime.

  This function is responsible to check if a given query is an
  `Ecto.Query.Query` record at compile time or not and act
  accordingly.

  If a query is available, it invokes the `apply` function in the
  given `module`, otherwise, it delegates the call to runtime.

  It is important to keep in mind the complexities introduced
  by this function. In particular, a Query[] is mixture of escaped
  and unescaped expressions which makes it impossible for this
  function to properly escape or unescape it at compile/runtime.
  For this reason, the apply function should be ready to handle
  arguments in both escaped and unescaped form.

  For example, take into account the `SelectBuilder`:

      select  = Ecto.Query.QueryExpr[expr: expr, file: env.file, line: env.line]
      BuilderUtil.apply_query(query, __MODULE__, [select], env)

  `expr` is already an escaped expression and we must not escape
  it again. However, it is wrapped in an Ecto.Query.QueryExpr,
  which must be escaped! Furthermore, the `apply/2` function
  in `SelectBuilder` very likely will inject the QueryExpr inside
  Query, which again, is a mixture of escaped and unescaped expressions.

  That said, you need to obey the following rules:

  1. In order to call this function, the arguments must be escapable
     values supported by the `escape/1` function below;

  2. The apply function not manipulate the given arguments,
     with exception by the query.

  In particular, when invoke at compilation time, all arguments
  (except the query) will be escaped, so they can be injected into
  the query properly, but they will be in their runtime form
  when invoked at runtime.
  """
  def apply_query(query, module, args, env) do
    query = Macro.expand(query, env)
    args  = lc i inlist args, do: escape_query(i)
    case unescape_query(query) do
      Query[] = unescaped ->
        apply(module, :apply, [unescaped|args]) |> escape_query
      _ ->
        quote do: unquote(module).apply(unquote_splicing([query|args]))
    end
  end

  @doc """
  Unescapes an `Ecto.Query.Query` record.
  """
  def unescape_query({ :{}, _meta, [Query|_] = query }),
    do: list_to_tuple(query)
  def unescape_query(other),
    do: other

  @doc """
  Escapes an `Ecto.Query.Query` and associated records.
  """
  def escape_query(Query[] = query),
    do: { :{}, [], tuple_to_list(query) }
  def escape_query(other),
    do: other
end
