defmodule Ecto.Query do

  defrecord Query, froms: [], wheres: [], select: nil
  defrecord QueryExpr, [:expr, :binding]

  # :!, :@, :^, :not, :+, :-

  defmacro unary_ops do
    [ :!, :+, :- ]
  end

  # :===, :!==,
  # :==, :!=, :<=, :>=,
  # :&&, :||, :<>, :++, :--, :**, ://, :::, :<-, :.., :|>, :=~,
  # :<, :>, :->,
  # :+, :-, :*, :/, :=, :|, :.,
  # :and, :or, :xor, :when, :in, :inlist, :inbits,
  # :<<<, :>>>, :|||, :&&&, :^^^, :~~~

  defmacro binary_ops do
    [ :==, :!=, :<=, :>=, :&&, :||, :<, :>, :+, :-, :*, :/ ]
  end

  defmacro from(query // Macro.escape(Query[]), expr) do
    check_from(expr)
    expr = expand_in(expr, __CALLER__) |> Macro.escape
    quote do
      Ecto.Query.merge(unquote(query), :from, unquote(expr), [])
    end
  end

  defmacro select(query, expr) do
    check_select(expr)
    vars = get_vars(expr)
    expr = Macro.escape(expr)
    quote do
      bind = binding(unquote(vars), true)
      Ecto.Query.merge(unquote(query), :select, unquote(expr), bind)
    end
  end

  defmacro where(query // Macro.escape(Query[]), expr) do
    check_expr(expr)
    vars = get_vars(expr)
    expr = Macro.escape(expr)
    quote do
      bind = binding(unquote(vars), true)
      Ecto.Query.merge(unquote(query), :where, unquote(expr), bind)
    end
  end

  def merge(left, right) do
    check_merge(left, right)

    Query[ froms: left.froms ++ right.froms,
           wheres: left.wheres ++ right.wheres,
           select: right.select ]
  end

  @doc false
  def merge(query, type, expr, binding) do
    query_expr = QueryExpr[expr: expr, binding: binding]
    check_merge(query, Query.new([{ type, query_expr }]))

    case type do
      :from   -> query.update_froms(&1 ++ [query_expr])
      :where  -> query.update_wheres(&1 ++ [query_expr])
      :select -> query.select(query_expr)
    end
  end

  # TODO: Check variable collision and make sure that all variables are bound
  def validate(query) do
    _from_bound = Enum.reduce(query.froms, [], fn(from, acc) ->
      { :in, _, [var, _record] } = from.expr
      [var|acc]
    end)
  end

  defp expand_in({ :in, meta, [left, right] }, env) do
    right = Macro.expand(right, env)
    { :in, meta, [left, right] }
  end

  defp check_merge(left, _right) do
    if left.select do
      raise ArgumentError, message: "cannot append to query where result is selected"
    end
  end

  defp check_from({ :in, _, [left, right] }) do
    if not ast_is_var?(left) do
      raise ArgumentError, message: "left hand side of `in` must be a variable"
    end

    if not ast_is_alias?(right) do
      raise ArgumentError, message: "right hand side of `in` must be a module name"
    end
  end

  defp check_from(_) do
    raise ArgumentError, message: "from expressions must be in `var in Record` format"
  end

  # TODO: Allow records
  defp check_select({ :"{}", _, elems }) do
    Enum.each(elems, check_select(&1))
  end

  defp check_select({ x, y }) do
    check_select({ :"{}", [], [x, y] })
  end

  defp check_select(list) when is_list(list) do
    Enum.map(list, check_select(&1))
  end

  defp check_select(ast) do
    check_expr(ast)
  end

  defp check_expr({ :"{}", _, _elems }) do
    raise ArgumentError, message: "tuples are not allowed in query expressions"
  end

  defp check_expr({ left, right }) do
    check_expr({ :"{}", [], [left, right] })
  end

  defp check_expr(list) when is_list(list) do
    raise ArgumentError, message: "lists are not allowed in query expressions"
  end

  defp check_expr({ { :., _, [Kernel, :access] }, _, _ }) do
    raise ArgumentError, message: "element access is not allowed in query expressions"
  end

  defp check_expr({ :., _, [left, right] }) do
    check_expr(left)
    check_expr(right)
  end

  defp check_expr({ op, _, [ast] }) do
    if not op in unary_ops do
      raise ArgumentError, message: "binary expression `#{op}` is not allowed in query expressions"
    end
    check_expr(ast)
  end

  defp check_expr({ op, _, [left, right] }) do
    if not op in binary_ops do
      raise ArgumentError, message: "binary expression `#{op}` is not allowed in query expressions"
    end
    check_expr(left)
    check_expr(right)
  end

  defp check_expr({ left, _, right }) do
    check_expr(left)
    if not (is_atom(right) || right == []) do
      raise ArgumentError, message: "function calls are not allowed in query exressions"
    end
  end

  defp check_expr(x) when is_binary(x) or is_number(x) or is_atom(x) do
    :ok
  end


  defp get_vars(ast), do: get_vars(ast, [])

  defp get_vars({ var, _, scope }, acc) when is_atom(var) and is_atom(scope) do
    [{ var, scope }|acc]
  end

  defp get_vars({ left, _, right }, acc) do
    get_vars(right, get_vars(left, acc))
  end

  defp get_vars({ left, right }, acc) do
    get_vars(right, get_vars(left, acc))
  end

  defp get_vars(list, acc) when is_list(list) do
    Enum.reduce list, acc, get_vars(&1, &2)
  end

  defp get_vars(_, acc), do: acc


  defp ast_is_var?({ var, _, scope }) when is_atom(var) and is_atom(scope), do: true
  defp ast_is_var?(_), do: false

  defp ast_is_alias?({ :__aliases__, _, _ }), do: true
  defp ast_is_alias?(_), do: false
end
