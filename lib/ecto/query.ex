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
    check_where(expr)
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

  def validate(query) do
    if query.select == nil do
      raise ArgumentError, message: "a query must have a select expression"
    end

    if query.froms == [] do
      raise ArgumentError, message: "a query must have a from expression"
    end

    # TODO: Check variable collision and make sure that all variables are bound,
    #       also check types when we know the types of bindings
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

  defp check_where(expr) do
    unless check_expr(expr) in [:boolean, :any] do
      raise ArgumentError, message: "where expressions must be of boolean type"
    end
  end

  # TODO: Allow records
  defp check_select({ :"{}", _, elems }) do
    Enum.each(elems, check_select(&1))
    :tuple
  end

  defp check_select({ x, y }) do
    check_select({ :"{}", [], [x, y] })
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
    :any
  end

  defp check_expr({ op, _, [left, right] }) when op in [:==, :!=] do
    left_type = check_expr(left)
    right_type = check_expr(right)
    unless left_type == right_type or :any in [left_type, right_type] do
      raise ArgumentError, message: "left and right operands' types must match for `#{op}`"
    end
    :boolean
  end

  defp check_expr({ op, _, [left, right] }) when op in [:+, :-, :*, :/] do
    left_type = check_expr(left)
    right_type = check_expr(right)
    unless left_type in [:number, :any] and right_type in [:number, :any] do
      raise ArgumentError, message: "`#{op}` is only supported on number types"
    end
    :number
  end

  defp check_expr({ op, _, [left, right] }) when op in [:<=, :>=, :<, :>] do
    left_type = check_expr(left)
    right_type = check_expr(right)
    unless left_type in [:number, :any] and right_type in [:number, :any] do
      raise ArgumentError, message: "`#{op}` is only supported on number types"
    end
    :boolean
  end

  defp check_expr({ op, _, [left, right] }) when op in [:&&, :||] do
    left_type = check_expr(left)
    right_type = check_expr(right)
    unless left_type in [:boolean, :any] and right_type in [:boolean, :any]  do
      raise ArgumentError, message: "`#{op}` is only supported on boolean types"
    end
    :boolean
  end

  defp check_expr({ :!, _, [ast] }) do
    unless check_expr(ast) in [:boolean, :any] do
      raise ArgumentError, message: "`!` is only supported on boolean types"
    end
    :boolean
  end

  defp check_expr({ op, _, [ast] }) when op in [:+, :-] do
    unless check_expr(ast) in [:number, :any] do
      raise ArgumentError, message: "`#{op}` is only supported on number types"
    end
    :number
  end

  defp check_expr({ op, _, [_] }) do
    raise ArgumentError, message: "unary expression `#{op}` is not allowed in query expressions"
  end

  defp check_expr({ op, _, [_, _] }) do
    raise ArgumentError, message: "binary expression `#{op}` is not allowed in query expressions"
  end

  defp check_expr({ var, _, atom }) when is_atom(var) and is_atom(atom) do
    :any
  end

  defp check_expr({ ast, _, [] }) when is_tuple(ast) do
    check_expr(ast)
  end

  defp check_expr({ _ast, _, list }) when is_list(list) do
    raise ArgumentError, message: "function calls are not allowed in query expressions"
  end

  defp check_expr(nil), do: :boolean
  defp check_expr(true), do: :boolean
  defp check_expr(false), do: :boolean
  defp check_expr(atom) when is_atom(atom), do: :any
  defp check_expr(number) when is_number(number), do: :number
  defp check_expr(boolean) when is_boolean(boolean), do: :boolean
  defp check_expr(string) when is_binary(string), do: :string


  defp get_vars(ast), do: get_vars(ast, []) |> Enum.uniq

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
