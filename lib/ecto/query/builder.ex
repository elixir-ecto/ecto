defmodule Ecto.Query.Builder do
  @moduledoc false

  alias Ecto.Query

  @comparisons [
    is_nil: 1,
    ==: 2,
    !=: 2,
    <: 2,
    >: 2,
    <=: 2,
    >=: 2
  ]

  @dynamic_aggregates [
    max: 1,
    min: 1,
    first_value: 1,
    last_value: 1,
    nth_value: 2,
    lag: 3,
    lead: 3,
    lag: 2,
    lead: 2,
    lag: 1,
    lead: 1
  ]

  @static_aggregates [
    count: {0, :integer},
    count: {1, :integer},
    count: {2, :integer},
    avg: {1, :any},
    sum: {1, :any},
    row_number: {0, :integer},
    rank: {0, :integer},
    dense_rank: {0, :integer},
    percent_rank: {0, :any},
    cume_dist: {0, :any},
    ntile: {1, :integer}
  ]

  @select_alias_dummy_value []

  @typedoc """
  Quoted types store primitive types and types in the format
  {source, quoted}. The latter are handled directly in the planner,
  never forwarded to Ecto.Type.

  The Ecto.Type module concerns itself only with runtime types,
  which include all primitive types and custom user types. Also
  note custom user types do not show up during compilation time.
  """
  @type quoted_type :: Ecto.Type.primitive | {non_neg_integer, atom | Macro.t}

  @typedoc """
  The accumulator during escape.

  If the subqueries field is available, subquery escaping must take place.
  """
  @type acc :: %{
          optional(:subqueries) => list(Macro.t()),
          optional(:take) => %{non_neg_integer => Macro.t()},
          optional(any) => any
        }

  @doc """
  Smart escapes a query expression and extracts interpolated values in
  a map.

  Everything that is a query expression will be escaped, interpolated
  expressions (`^foo`) will be moved to a map unescaped and replaced
  with `^index` in the query where index is a number indexing into the
  map.
  """
  @spec escape(Macro.t, quoted_type | {:in, quoted_type} | {:out, quoted_type}, {list, acc},
               Keyword.t, Macro.Env.t | {Macro.Env.t, fun}) :: {Macro.t, {list, acc}}
  def escape(expr, type, params_acc, vars, env)

  # var.x - where var is bound
  def escape({{:., _, [callee, field]}, _, []}, _type, params_acc, vars, _env) when is_atom(field) do
    {escape_field!(callee, field, vars), params_acc}
  end

  # field macro
  def escape({:field, _, [callee, field]}, _type, params_acc, vars, _env) do
    {escape_field!(callee, field, vars), params_acc}
  end

  # param interpolation
  def escape({:^, _, [arg]}, type, {params, acc}, _vars, _env) do
    expr = {:{}, [], [:^, [], [length(params)]]}
    params = [{arg, type} | params]
    {expr, {params, acc}}
  end

  # tagged types
  def escape({:type, _, [{:^, _, [arg]}, type]}, _type, {params, acc}, vars, env) do
    type = validate_type!(type, vars, env)
    expr = {:{}, [], [:type, [], [{:{}, [], [:^, [], [length(params)]]}, type]]}
    params = [{arg, type} | params]
    {expr, {params, acc}}
  end

  def escape({:type, _, [{{:., _, [{var, _, context}, field]}, _, []} = expr, type]}, _type, params_acc, vars, env)
      when is_atom(var) and is_atom(context) and is_atom(field) do
    escape_with_type(expr, type, params_acc, vars, env)
  end

  def escape({:type, _, [{:coalesce, _, [_ | _]} = expr, type]}, _type, params_acc, vars, env) do
    escape_with_type(expr, type, params_acc, vars, env)
  end

  def escape({:type, _, [{:field, _, [_ | _]} = expr, type]}, _type, params_acc, vars, env) do
    escape_with_type(expr, type, params_acc, vars, env)
  end

  def escape({:type, _, [{math_op, _, [_, _]} = op_expr, type]}, _type, params_acc, vars, env)
      when math_op in ~w(+ - * /)a do
    escape_with_type(op_expr, type, params_acc, vars, env)
  end

  def escape({:type, _, [{fun, _, args} = expr, type]}, _type, params_acc, vars, env)
      when is_list(args) and fun in ~w(fragment avg count max min sum over filter)a do
    escape_with_type(expr, type, params_acc, vars, env)
  end

  def escape({:type, _, [{:json_extract_path, _, [_ | _]} = expr, type]}, _type, params_acc, vars, env) do
    escape_with_type(expr, type, params_acc, vars, env)
  end

  def escape({:type, _, [{{:., _, [Access, :get]}, _, _} = access_expr, type]}, _type, params_acc, vars, env) do
    escape_with_type(access_expr, type, params_acc, vars, env)
  end

  def escape({:type, _, [{{:., _, [{:parent_as, _, [_parent]}, _field]}, _, []} = expr, type]}, _type, params_acc, vars, env) do
    escape_with_type(expr, type, params_acc, vars, env)
  end

  def escape({:type, meta, [expr, type]}, given_type, params_acc, vars, env) do
    case Macro.expand_once(expr, get_env(env)) do
      ^expr ->
        error! """
        the first argument of type/2 must be one of:

          * interpolations, such as ^value
          * fields, such as p.foo or field(p, :foo)
          * fragments, such as fragment("foo(?)", value)
          * an arithmetic expression (+, -, *, /)
          * an aggregation or window expression (avg, count, min, max, sum, over, filter)
          * a conditional expression (coalesce)
          * access/json paths (p.column[0].field)
          * parent_as/1 (parent_as(:parent).field)

        Got: #{Macro.to_string(expr)}
        """

      expanded ->
        escape({:type, meta, [expanded, type]}, given_type, params_acc, vars, env)
    end
  end

  # fragments
  def escape({:fragment, _, [query]}, _type, params_acc, vars, env) when is_list(query) do
    {escaped, params_acc} =
      Enum.map_reduce(query, params_acc, &escape_kw_fragment(&1, &2, vars, env))
    {{:{}, [], [:fragment, [], [escaped]]}, params_acc}
  end

  def escape({:fragment, _, [{:^, _, [var]} = _expr]}, _type, params_acc, _vars, _env) do
    expr = quote do: Ecto.Query.Builder.fragment!(unquote(var))
    {{:{}, [], [:fragment, [], [expr]]}, params_acc}
  end

  def escape({:fragment, _, [query | frags]}, _type, params_acc, vars, env) do
    pieces = expand_and_split_fragment(query, env)

    if length(pieces) != length(frags) + 1 do
      error! "fragment(...) expects extra arguments in the same amount of question marks in string. " <>
               "It received #{length(frags)} extra argument(s) but expected #{length(pieces) - 1}"
    end

    {frags, params_acc} = Enum.map_reduce(frags, params_acc, &escape_fragment(&1, &2, vars, env))
    {{:{}, [], [:fragment, [], merge_fragments(pieces, frags)]}, params_acc}
  end

  # subqueries
  def escape({:subquery, _, [expr]}, _, {params, %{subqueries: subqueries} = acc}, _vars, _env) do
    subquery = quote(do: Ecto.Query.subquery(unquote(expr)))
    index = length(subqueries)
    # used both in ast and in parameters, as a placeholder.
    expr = {:subquery, index}
    acc = %{acc | subqueries: [subquery | subqueries]}
    {expr, {[expr | params], acc}}
  end

  # interval

  def escape({:from_now, meta, [count, interval]}, type, params_acc, vars, env) do
    utc = quote do: ^DateTime.utc_now()
    escape({:datetime_add, meta, [utc, count, interval]}, type, params_acc, vars, env)
  end

  def escape({:ago, meta, [count, interval]}, type, params_acc, vars, env) do
    utc = quote do: ^DateTime.utc_now()
    count =
      case count do
        {:^, meta, [value]} ->
          negate = quote do: Ecto.Query.Builder.negate!(unquote(value))
          {:^, meta, [negate]}
        value ->
          {:-, [], [value]}
      end
    escape({:datetime_add, meta, [utc, count, interval]}, type, params_acc, vars, env)
  end

  def escape({:datetime_add, _, [datetime, count, interval]} = expr, type, params_acc, vars, env) do
    assert_type!(expr, type, {:param, :any_datetime})
    {datetime, params_acc} = escape(datetime, {:param, :any_datetime}, params_acc, vars, env)
    {count, interval, params_acc} = escape_interval(count, interval, params_acc, vars, env)
    {{:{}, [], [:datetime_add, [], [datetime, count, interval]]}, params_acc}
  end

  def escape({:date_add, _, [date, count, interval]} = expr, type, params_acc, vars, env) do
    assert_type!(expr, type, :date)
    {date, params_acc} = escape(date, :date, params_acc, vars, env)
    {count, interval, params_acc} = escape_interval(count, interval, params_acc, vars, env)
    {{:{}, [], [:date_add, [], [date, count, interval]]}, params_acc}
  end

  # json
  def escape({:json_extract_path, _, [field, path]} = expr, type, params_acc, vars, env) do
    case field do
      {{:., _, _}, _, _} ->
        path = escape_json_path(path)
        {field, params_acc} = escape(field, type, params_acc, vars, env)
        {{:{}, [], [:json_extract_path, [], [field, path]]}, params_acc}

      _ ->
        error!("`#{Macro.to_string(expr)}` is not a valid query expression")
    end
  end

  def escape({{:., meta, [Access, :get]}, _, [left, _]} = expr, type, params_acc, vars, env) do
    case left do
      {{:., _, _}, _, _} ->
        {expr, path} = parse_access_get(expr, [])
        escape({:json_extract_path, meta, [expr, path]}, type, params_acc, vars, env)

      _ ->
        error!("`#{Macro.to_string(expr)}` is not a valid query expression")
    end
  end

  # sigils
  def escape({name, _, [_, []]} = sigil, type, params_acc, vars, _env)
      when name in ~w(sigil_s sigil_S sigil_w sigil_W)a do
    {literal(sigil, type, vars), params_acc}
  end

  # lists
  def escape(list, type, params_acc, vars, env) when is_list(list) do
    if Enum.all?(list, &is_binary(&1) or is_number(&1) or is_boolean(&1)) do
      {literal(list, type, vars), params_acc}
    else
      fun =
        case type do
          {:array, inner_type} ->
            &escape(&1, inner_type, &2, vars, env)

          _ ->
            # In case we don't have an array nor a literal at compile-time,
            # such as p.links == [^value], we don't do any casting nor validation.
            # We may want to tackle this if the expression above is ever used.
            &escape(&1, :any, &2, vars, env)
        end

      Enum.map_reduce(list, params_acc, fun)
    end
  end

  # literals
  def escape({:<<>>, _, args} = expr, type, params_acc, vars, _env) do
    valid? = Enum.all?(args, fn
      {:"::", _, [left, _]} -> is_integer(left) or is_binary(left)
      left -> is_integer(left) or is_binary(left)
    end)

    unless valid? do
      error! "`#{Macro.to_string(expr)}` is not a valid query expression. " <>
             "Only literal binaries and strings are allowed, " <>
             "dynamic values need to be explicitly interpolated in queries with ^"
    end

    {literal(expr, type, vars), params_acc}
  end

  def escape({:-, _, [number]}, type, params_acc, vars, _env) when is_number(number),
    do: {literal(-number, type, vars), params_acc}
  def escape(number, type, params_acc, vars, _env) when is_number(number),
    do: {literal(number, type, vars), params_acc}
  def escape(binary, type, params_acc, vars, _env) when is_binary(binary),
    do: {literal(binary, type, vars), params_acc}
  def escape(nil, _type, params_acc, _vars, _env),
    do: {nil, params_acc}
  def escape(atom, type, params_acc, vars, _env) when is_atom(atom),
    do: {literal(atom, type, vars), params_acc}

  # negate any expression
  def escape({:-, meta, arg}, type, params_acc, vars, env) do
    {escaped_arg, params_acc} = escape(arg, type, params_acc, vars, env)
    expr = {:{}, [], [:-, meta, escaped_arg]}
    {expr, params_acc}
  end

  # comparison operators
  def escape({comp_op, _, [left, right]} = expr, type, params_acc, vars, env)
      when comp_op in ~w(== != < > <= >=)a do
    assert_type!(expr, type, :boolean)

    if is_nil(left) or is_nil(right) do
      error! "comparison with nil is forbidden as it is unsafe. " <>
             "If you want to check if a value is nil, use is_nil/1 instead"
    end

    ltype = quoted_type(right, vars)
    rtype = quoted_type(left, vars)

    {left,  params_acc} = escape(left, ltype, params_acc, vars, env)
    {right, params_acc} = escape(right, rtype, params_acc, vars, env)

    {params, acc} = params_acc
    {{:{}, [], [comp_op, [], [left, right]]},
     {params |> wrap_nil(left) |> wrap_nil(right), acc}}
  end

  # mathematical operators
  def escape({math_op, _, [left, right]}, type, params_acc, vars, env)
      when math_op in ~w(+ - * /)a do
    {left,  params_acc} = escape(left, type, params_acc, vars, env)
    {right, params_acc} = escape(right, type, params_acc, vars, env)

    {{:{}, [], [math_op, [], [left, right]]}, params_acc}
  end

  # in operator
  def escape({:in, _, [left, right]} = expr, type, params_acc, vars, env)
      when is_list(right)
      when is_tuple(right) and elem(right, 0) in ~w(sigil_w sigil_W)a do
    assert_type!(expr, type, :boolean)

    {:array, ltype} = quoted_type(right, vars)
    rtype = {:array, quoted_type(left, vars)}

    {left, params_acc} = escape(left, ltype, params_acc, vars, env)
    {right, params_acc} = escape(right, rtype, params_acc, vars, env)
    {{:{}, [], [:in, [], [left, right]]}, params_acc}
  end

  def escape({:in, _, [left, right]} = expr, type, params_acc, vars, env) do
    assert_type!(expr, type, :boolean)

    ltype = {:out, quoted_type(right, vars)}
    rtype = {:in, quoted_type(left, vars)}

    {left, params_acc} = escape(left, ltype, params_acc, vars, env)
    {right, params_acc} = escape(right, rtype, params_acc, vars, env)

    # Remove any type wrapper from the right side
    right =
      case right do
        {:{}, [], [:type, [], [right, _]]} -> right
        _ -> right
      end

    {{:{}, [], [:in, [], [left, right]]}, params_acc}
  end

  def escape({:count, _, [arg, :distinct]}, type, params_acc, vars, env) do
    {arg, params_acc} = escape(arg, type, params_acc, vars, env)
    expr = {:{}, [], [:count, [], [arg, :distinct]]}
    {expr, params_acc}
  end

  def escape({:filter, _, [aggregate]}, type, params_acc, vars, env) do
    escape(aggregate, type, params_acc, vars, env)
  end

  def escape({:filter, _, [aggregate, filter_expr]}, type, params_acc, vars, env) do
    {aggregate, params_acc} = escape(aggregate, type, params_acc, vars, env)
    {filter_expr, params_acc} = escape(filter_expr, :boolean, params_acc, vars, env)
    {{:{}, [], [:filter, [], [aggregate, filter_expr]]}, params_acc}
  end

  def escape({:coalesce, _, [left, right]}, type, params_acc, vars, env) do
    {left, params_acc} = escape(left, type, params_acc, vars, env)
    {right, params_acc} = escape(right, type, params_acc, vars, env)
    {{:{}, [], [:coalesce, [], [left, right]]}, params_acc}
  end

  def escape({:over, _, [{agg_name, _, agg_args} | over_args]}, type, params_acc, vars, env) do
    aggregate = {agg_name, [], agg_args || []}
    {aggregate, params_acc} = escape_window_function(aggregate, type, params_acc, vars, env)
    {window, params_acc} = escape_window_description(over_args, params_acc, vars, env)
    {{:{}, [], [:over, [], [aggregate, window]]}, params_acc}
  end

  def escape({:selected_as, _, [_expr, _name]}, _type, _params_acc, _vars, _env) do
    error! """
    selected_as/2 can only be used at the root of a select statement. \
    If you are trying to use it inside of an expression, consider putting the \
    expression inside of `selected_as/2` instead. For instance, instead of:

        from p in Post, select: coalesce(selected_as(p.visits, :v), 0)

    use:

        from p in Post, select: selected_as(coalesce(p.visits, 0), :v)
    """
  end

  def escape({:selected_as, _, [name]}, _type, params_acc, _vars, _env) when is_atom(name) do
    expr = {:{}, [], [:selected_as, [], [name]]}
    {expr, params_acc}
  end

  def escape({:selected_as, _, [name]}, _type, _params_acc, _vars, _env) do
    error! "selected_as/1 expects `name` to be an atom, got `#{inspect(name)}`"
  end

  def escape({quantifier, meta, [subquery]}, type, params_acc, vars, env) when quantifier in [:all, :any, :exists] do
    {subquery, params_acc} = escape({:subquery, meta, [subquery]}, type, params_acc, vars, env)
    {{:{}, [], [quantifier, [], [subquery]]}, params_acc}
  end

  def escape({:=, _, _} = expr, _type, _params_acc, _vars, _env) do
    error! "`#{Macro.to_string(expr)}` is not a valid query expression. " <>
            "The match operator is not supported: `=`. " <>
            "Did you mean to use `==` instead?"
  end

  def escape({op, _, _}, _type, _params_acc, _vars, _env) when op in ~w(|| && !)a do
    error! "short-circuit operators are not supported: `#{op}`. " <>
           "Instead use boolean operators: `and`, `or`, and `not`"
  end

  # Tuple
  def escape({left, right}, type, params_acc, vars, env) do
    escape({:{}, [], [left, right]}, type, params_acc, vars, env)
  end

  # Tuple
  def escape({:{}, _, list}, {:tuple, types}, params_acc, vars, env) do
    if Enum.count(list) == Enum.count(types) do
      {list, params_acc} =
        list
        |> Enum.zip(types)
        |> Enum.map_reduce(params_acc, fn {expr, type}, params_acc ->
             escape(expr, type, params_acc, vars, env)
           end)
      expr = {:{}, [], [:{}, [], list]}
      {expr, params_acc}
    else
      escape({:{}, [], list}, :any, params_acc, vars, env)
    end
  end

  # Tuple
  def escape({:{}, _, _}, _, _, _, _) do
    error! "Tuples can only be used in comparisons with literal tuples of the same size"
  end

  # Unnecessary parentheses around an expression
  def escape({:__block__, _, [expr]}, type, params_acc, vars, env) do
    escape(expr, type, params_acc, vars, env)
  end

  # Other functions - no type casting
  def escape({name, _, args} = expr, type, params_acc, vars, env) when is_atom(name) and is_list(args) do
    case call_type(name, length(args)) do
      {in_type, out_type} ->
        assert_type!(expr, type, out_type)
        escape_call(expr, in_type, params_acc, vars, env)
      nil ->
        try_expansion(expr, type, params_acc, vars, env)
    end
  end

  # Finally handle vars
  def escape({var, _, context}, _type, params_acc, vars, _env) when is_atom(var) and is_atom(context) do
    {escape_var!(var, vars), params_acc}
  end

  # Raise nice error messages for fun calls.
  def escape({fun, _, args} = other, _type, _params_acc, _vars, _env)
      when is_atom(fun) and is_list(args) do
    error! """
    `#{Macro.to_string(other)}` is not a valid query expression. \
    If you are trying to invoke a function that is not supported by Ecto, \
    you can use fragments:

        fragment("some_function(?, ?, ?)", m.some_field, 1)

    See Ecto.Query.API to learn more about the supported functions and \
    Ecto.Query.API.fragment/1 to learn more about fragments.
    """
  end

  # Raise nice error message for remote calls
  def escape({{:., _, [_, fun]}, _, _} = other, type, params_acc, vars, env)
      when is_atom(fun) do
    try_expansion(other, type, params_acc, vars, env)
  end

  # For everything else we raise
  def escape(other, _type, _params_acc, _vars, _env) do
    error! "`#{Macro.to_string(other)}` is not a valid query expression"
  end

  defp escape_with_type(expr, {:^, _, [type]}, params_acc, vars, env) do
    {expr, params_acc} = escape(expr, :any, params_acc, vars, env)
    {{:{}, [], [:type, [], [expr, type]]}, params_acc}
  end

  defp escape_with_type(expr, type, params_acc, vars, env) do
    type = validate_type!(type, vars, env)
    {expr, params_acc} = escape(expr, type, params_acc, vars, env)
    {{:{}, [], [:type, [], [expr, escape_type(type)]]}, params_acc}
  end

  defp escape_type({:parameterized, _, _} = param), do: Macro.escape(param)
  defp escape_type(type), do: type

  defp wrap_nil(params, {:{}, _, [:^, _, [ix]]}), do: wrap_nil(params, length(params) - ix - 1, [])
  defp wrap_nil(params, _other), do: params

  defp wrap_nil([{val, type} | params], 0, acc) do
    val = quote do: Ecto.Query.Builder.not_nil!(unquote(val))
    Enum.reverse(acc, [{val, type} | params])
  end

  defp wrap_nil([pair | params], i, acc) do
    wrap_nil(params, i - 1, [pair | acc])
  end

  defp expand_and_split_fragment(query, env) do
    case Macro.expand(query, get_env(env)) do
      binary when is_binary(binary) ->
        split_fragment(binary, "")

      _ ->
        error! bad_fragment_message(Macro.to_string(query))
    end
  end

  defp bad_fragment_message(arg) do
    "to prevent SQL injection attacks, fragment(...) does not allow strings " <>
      "to be interpolated as the first argument via the `^` operator, got: `#{arg}`"
  end

  defp split_fragment(<<>>, consumed),
    do: [consumed]
  defp split_fragment(<<??, rest :: binary>>, consumed),
    do: [consumed | split_fragment(rest, "")]
  defp split_fragment(<<?\\, ??, rest :: binary>>, consumed),
    do: split_fragment(rest, consumed <> <<??>>)
  defp split_fragment(<<first :: utf8, rest :: binary>>, consumed),
    do: split_fragment(rest, consumed <> <<first :: utf8>>)

  @doc "Returns fragment pieces, given a fragment string and arguments."
  def fragment_pieces(frag, args) do
    frag
    |> split_fragment("")
    |> merge_fragments(args)
  end

  defp escape_window_description([], params_acc, _vars, _env),
    do: {[], params_acc}
  defp escape_window_description([window_name], params_acc, _vars, _env) when is_atom(window_name),
    do: {window_name, params_acc}
  defp escape_window_description([kw], params_acc, vars, env) do
    case Ecto.Query.Builder.Windows.escape(kw, params_acc, vars, env) do
      {runtime, [], params_acc} ->
        {runtime, params_acc}

      {_, [{key, _} | _], _} ->
        error! "windows definitions given to over/2 do not allow interpolations at the root of " <>
                 "`#{key}`. Please use Ecto.Query.windows/3 to explicitly define a window instead"
    end
  end

  defp escape_window_function(expr, type, params_acc, vars, env) do
    expr
    |> validate_window_function!(env)
    |> escape(type, params_acc, vars, env)
  end

  defp validate_window_function!({:fragment, _, _} = expr, _env), do: expr

  defp validate_window_function!({agg, _, args} = expr, env)
       when is_atom(agg) and is_list(args) do
    if Code.ensure_loaded?(Ecto.Query.WindowAPI) and
         function_exported?(Ecto.Query.WindowAPI, agg, length(args)) do
      expr
    else
      case Macro.expand_once(expr, get_env(env)) do
        ^expr ->
          error! "unknown window function #{agg}/#{length(args)}. " <>
                   "See Ecto.Query.WindowAPI for all available functions"
        expr ->
          validate_window_function!(expr, env)
      end
    end
  end

  defp validate_window_function!(expr, _), do: expr

  defp escape_call({name, _, args}, type, params_acc, vars, env) do
    {args, params_acc} = Enum.map_reduce(args, params_acc, &escape(&1, type, &2, vars, env))
    expr = {:{}, [], [name, [], args]}
    {expr, params_acc}
  end

  defp escape_field!({var, _, context}, field, vars)
       when is_atom(var) and is_atom(context) do
    var   = escape_var!(var, vars)
    field = quoted_atom!(field, "field/2")
    dot   = {:{}, [], [:., [], [var, field]]}
    {:{}, [], [dot, [], []]}
  end

  defp escape_field!({kind, _, [value]}, field, _vars)
       when kind in [:as, :parent_as] do
    value =
      case value do
        {:^, _, [value]} ->
          value

        other ->
          quoted_atom!(other, "#{kind}/1")
      end
    as    = {:{}, [], [kind, [], [value]]}
    field = quoted_atom!(field, "field/2")
    dot   = {:{}, [], [:., [], [as, field]]}
    {:{}, [], [dot, [], []]}
  end

  defp escape_field!(expr, field, _vars) do
    error!("""
    cannot fetch field `#{field}` from `#{Macro.to_string(expr)}`. Can only fetch fields from:

      * sources, such as `p` in `from p in Post`
      * named bindings, such as `as(:post)` in `from Post, as: :post`
      * parent named bindings, such as `parent_as(:post)` in a subquery
    """)
  end

  defp escape_interval(count, interval, params_acc, vars, env) do
    type =
      cond do
        is_float(count)   -> :float
        is_integer(count) -> :integer
        true              -> :decimal
      end

    {count, params_acc} = escape(count, type, params_acc, vars, env)
    {count, quoted_interval!(interval), params_acc}
  end

  defp escape_kw_fragment({key, [{_, _}|_] = exprs}, params_acc, vars, env) when is_atom(key) do
    {escaped, params_acc} = Enum.map_reduce(exprs, params_acc, &escape_kw_fragment(&1, &2, vars, env))
    {{key, escaped}, params_acc}
  end

  defp escape_kw_fragment({key, expr}, params_acc, vars, env) when is_atom(key) do
    {escaped, params_acc} = escape(expr, :any, params_acc, vars, env)
    {{key, escaped}, params_acc}
  end

  defp escape_kw_fragment({key, _expr}, _params_acc, _vars, _env) do
    error! "fragment(...) with keywords accepts only atoms as keys, got `#{Macro.to_string(key)}`"
  end

  defp escape_fragment({:literal, _meta, [expr]}, params_acc, _vars, _env) do
    case expr do
      {:^, _, [expr]} ->
        checked = quote do: Ecto.Query.Builder.literal!(unquote(expr))
        escaped = {:{}, [], [:literal, [], [checked]]}
        {escaped, params_acc}

      _ ->
        error! "literal/1 in fragment expects an interpolated value, such as literal(^value), got `#{Macro.to_string(expr)}`"
    end
  end

  defp escape_fragment(expr, params_acc, vars, env) do
    escape(expr, :any, params_acc, vars, env)
  end

  defp merge_fragments([h1|t1], [h2|t2]),
    do: [{:raw, h1}, {:expr, h2} | merge_fragments(t1, t2)]

  defp merge_fragments([h1], []),
    do: [{:raw, h1}]

  for {agg, arity} <- @dynamic_aggregates do
    defp call_type(unquote(agg), unquote(arity)), do: {:any, :any}
  end

  for {agg, {arity, return}} <- @static_aggregates do
    defp call_type(unquote(agg), unquote(arity)), do: {:any, unquote(return)}
  end

  for {comp, arity} <- @comparisons do
    defp call_type(unquote(comp), unquote(arity)), do: {:any, :boolean}
  end

  defp call_type(:or, 2), do: {:boolean, :boolean}
  defp call_type(:and, 2), do: {:boolean, :boolean}
  defp call_type(:not, 1), do: {:boolean, :boolean}
  defp call_type(:like, 2), do: {:string, :boolean}
  defp call_type(:ilike, 2), do: {:string, :boolean}
  defp call_type(_, _), do: nil

  defp assert_type!(expr, type, actual) do
    cond do
      not is_atom(type) and not Ecto.Type.primitive?(type) ->
        :ok

      Ecto.Type.match?(type, actual) ->
        :ok

      true ->
        error! "expression `#{Macro.to_string(expr)}` does not type check. " <>
               "It returns a value of type #{inspect actual} but a value of " <>
               "type #{inspect type} is expected"
    end
  end

  @doc """
  Validates the type with the given vars.
  """
  def validate_type!({composite, type}, vars, env),
    do: {composite, validate_type!(type, vars, env)}
  def validate_type!({:^, _, [type]}, _vars, _env),
    do: type
  def validate_type!({:__aliases__, _, _} = type, _vars, env),
    do: Macro.expand(type, get_env(env))
  def validate_type!({:parameterized, _, _} = type, _vars, _env),
    do: type
  def validate_type!(type, _vars, _env) when is_atom(type),
    do: type
  def validate_type!({{:., _, [{var, _, context}, field]}, _, []}, vars, _env)
    when is_atom(var) and is_atom(context) and is_atom(field),
    do: {find_var!(var, vars), field}
  def validate_type!({:field, _, [{var, _, context}, field]}, vars, _env)
    when is_atom(var) and is_atom(context) and is_atom(field),
    do: {find_var!(var, vars), field}

  def validate_type!(type, _vars, _env) do
    error! "type/2 expects an alias, atom, initialized parameterized type or " <>
           "source.field as second argument, got: `#{Macro.to_string(type)}`"
  end

  @always_tagged [:binary]

  defp literal(value, expected, vars),
    do: do_literal(value, expected, quoted_type(value, vars))

  defp do_literal(value, _, current) when current in @always_tagged,
    do: {:%, [], [Ecto.Query.Tagged, {:%{}, [], [value: value, type: current]}]}
  defp do_literal(value, :any, _current),
    do: value
  defp do_literal(value, expected, expected),
    do: value
  defp do_literal(value, expected, _current),
    do: {:%, [], [Ecto.Query.Tagged, {:%{}, [], [value: value, type: expected]}]}

  @doc """
  Escape the params entries list.
  """
  @spec escape_params(list()) :: list()
  def escape_params(list), do: Enum.reverse(list)

  @doc """
  Escape the select alias map
  """
  @spec escape_select_aliases(map()) :: Macro.t
  def escape_select_aliases(%{} = aliases), do: {:%{}, [], Map.to_list(aliases)}

  @doc """
  Escapes a variable according to the given binds.

  A escaped variable is represented internally as
  `&0`, `&1` and so on.
  """
  @spec escape_var!(atom, Keyword.t) :: Macro.t
  def escape_var!(var, vars) do
    {:{}, [], [:&, [], [find_var!(var, vars)]]}
  end

  @doc """
  Escapes a list of bindings as a list of atoms.

  Only variables or `{:atom, value}` tuples are allowed in the `bindings` list,
  otherwise an `Ecto.Query.CompileError` is raised.

  ## Examples

      iex> escape_binding(%Ecto.Query{}, quote(do: [x, y, z]), __ENV__)
      {%Ecto.Query{}, [x: 0, y: 1, z: 2]}

      iex> escape_binding(%Ecto.Query{}, quote(do: [{x, 0}, {z, 2}]), __ENV__)
      {%Ecto.Query{}, [x: 0, z: 2]}

      iex> escape_binding(%Ecto.Query{}, quote(do: [x, y, x]), __ENV__)
      ** (Ecto.Query.CompileError) variable `x` is bound twice

      iex> escape_binding(%Ecto.Query{}, quote(do: [a, b, :foo]), __ENV__)
      ** (Ecto.Query.CompileError) binding list should contain only variables or `{as, var}` tuples, got: :foo

  """
  @spec escape_binding(Macro.t, list, Macro.Env.t) :: {Macro.t, Keyword.t}
  def escape_binding(query, binding, _env) when is_list(binding) do
    vars = binding |> Enum.with_index |> Enum.map(&escape_bind/1)
    assert_no_duplicate_binding!(vars)

    {positional_vars, named_vars} = Enum.split_while(vars, &not named_bind?(&1))
    assert_named_binds_in_tail!(named_vars, binding)

    {query, positional_binds} = calculate_positional_binds(query, positional_vars)
    {query, named_binds} = calculate_named_binds(query, named_vars)
    {query, positional_binds ++ named_binds}
  end
  def escape_binding(_query, bind, _env) do
    error! "binding should be list of variables and `{as, var}` tuples " <>
             "at the end, got: #{Macro.to_string(bind)}"
  end

  defp named_bind?({kind, _, _}), do: kind == :named

  defp assert_named_binds_in_tail!(named_vars, binding) do
    if Enum.all?(named_vars, &named_bind?/1) do
      :ok
    else
      error! "named binds in the form of `{as, var}` tuples must be at the end " <>
               "of the binding list, got: #{Macro.to_string(binding)}"
    end
  end

  defp assert_no_duplicate_binding!(vars) do
    bound_vars = for {_, var, _} <- vars, var != :_, do: var

    case bound_vars -- Enum.uniq(bound_vars) do
      []  -> :ok
      [var | _] -> error! "variable `#{var}` is bound twice"
    end
  end

  defp calculate_positional_binds(query, vars) do
    case Enum.split_while(vars, &elem(&1, 1) != :...) do
      {vars, []} ->
        vars = for {:pos, var, count} <- vars, do: {var, count}
        {query, vars}
      {vars, [_ | tail]} ->
        query =
          quote do
            query = Ecto.Queryable.to_query(unquote(query))
            escape_count = Ecto.Query.Builder.count_binds(query)
            query
          end

        tail =
          tail
          |> Enum.with_index(-length(tail))
          |> Enum.map(fn {{:pos, k, _}, count} -> {k, quote(do: escape_count + unquote(count))} end)

        vars = for {:pos, var, count} <- vars, do: {var, count}
        {query, vars ++ tail}
    end
  end

  defp calculate_named_binds(query, []), do: {query, []}
  defp calculate_named_binds(query, vars) do
    assignments =
      for {:named, key, name} <- vars do
        quote do
          unquote({key, [], __MODULE__}) = unquote(__MODULE__).count_alias!(query, unquote(name))
        end
      end

    query =
      quote do
        query = Ecto.Queryable.to_query(unquote(query))
        unquote_splicing(assignments)
        query
      end

    pairs =
      for {:named, key, _name} <- vars do
        {key, {key, [], __MODULE__}}
      end

    {query, pairs}
  end

  @doc """
  Count the alias for the given query.
  """
  def count_alias!(%{aliases: aliases} = query, name) do
    case aliases do
      %{^name => ix} ->
        ix

      %{} ->
        raise Ecto.QueryError, message: "unknown bind name `#{inspect name}`", query: query
    end
  end

  defp escape_bind({{{var, _, context}, ix}, _}) when is_atom(var) and is_atom(context),
    do: {:pos, var, ix}
  defp escape_bind({{var, _, context}, ix}) when is_atom(var) and is_atom(context),
    do: {:pos, var, ix}
  defp escape_bind({{name, {var, _, context}}, _ix}) when is_atom(name) and is_atom(var) and is_atom(context),
    do: {:named, var, name}
  defp escape_bind({{{:^, _, [expr]}, {var, _, context}}, _ix}) when is_atom(var) and is_atom(context),
    do: {:named, var, expr}
  defp escape_bind({bind, _ix}),
    do: error!("binding list should contain only variables or " <>
          "`{as, var}` tuples, got: #{Macro.to_string(bind)}")

  defp try_expansion(expr, type, params, vars, %Macro.Env{} = env) do
    try_expansion(expr, type, params, vars, {env, &escape/5})
  end

  defp try_expansion(expr, type, params, vars, {env, fun}) do
    case Macro.expand_once(expr, env) do
      ^expr ->
        error! """
        `#{Macro.to_string(expr)}` is not a valid query expression.

        * If you intended to call an Elixir function or introduce a value,
          you need to explicitly interpolate it with ^

        * If you intended to call a database function, please check the documentation
          for Ecto.Query.API to see the supported database expressions

        * If you intended to extend Ecto's query DSL, make sure that you have required
          the module or imported the relevant function. Note that you need macros to
          extend Ecto's querying capabilities
        """

      expanded ->
        fun.(expanded, type, params, vars, env)
    end
  end

  @doc """
  Finds the index value for the given var in vars or raises.
  """
  def find_var!(var, vars) do
    vars[var] || error! "unbound variable `#{var}` in query. If you are attempting to interpolate a value, use ^var"
  end

  @doc """
  Checks if the field is an atom at compilation time or
  delegate the check to runtime for interpolation.
  """
  def quoted_atom!({:^, _, [expr]}, used_ref),
    do: quote(do: Ecto.Query.Builder.atom!(unquote(expr), unquote(used_ref)))

  def quoted_atom!(atom, _used_ref) when is_atom(atom),
    do: atom

  def quoted_atom!(other, used_ref),
    do:
      error!(
        "expected literal atom or interpolated value in #{used_ref}, got: " <>
        "`#{Macro.to_string(other)}`"
      )

  @doc """
  Called by escaper at runtime to verify that value is an atom.
  """
  def atom!(atom, _used_ref) when is_atom(atom),
    do: atom

  def atom!(other, used_ref),
    do: error!("expected atom in #{used_ref}, got: `#{inspect other}`")

  defp escape_json_path(path) when is_list(path) do
    Enum.map(path, &quoted_json_path_element!/1)
  end

  defp escape_json_path({:^, _, [path]})  do
    quote do
      path = Ecto.Query.Builder.json_path!(unquote(path))
      Enum.map(path, &Ecto.Query.Builder.json_path_element!/1)
    end
  end

  defp escape_json_path(other) do
    error!("expected JSON path to be a literal list or interpolated value, got: `#{Macro.to_string(other)}`")
  end

  defp quoted_json_path_element!({:^, _, [expr]}),
    do: quote(do: Ecto.Query.Builder.json_path_element!(unquote(expr)))

  defp quoted_json_path_element!(binary) when is_binary(binary),
    do: binary

  defp quoted_json_path_element!(integer) when is_integer(integer),
    do: integer

  defp quoted_json_path_element!(other),
    do:
      error!(
        "expected JSON path to contain literal strings, literal integers, or interpolated values, got: " <>
        "`#{Macro.to_string(other)}`"
      )

  @doc """
  Called by escaper at runtime to verify that value is a string or an integer.
  """
  def json_path_element!(binary) when is_binary(binary),
    do: binary
  def json_path_element!(integer) when is_integer(integer),
    do: integer
  def json_path_element!(other),
    do: error!("expected string or integer in json_extract_path/2, got: `#{inspect other}`")

  @doc """
  Called by escaper at runtime to verify that path is a list
  """
  def json_path!(path) when is_list(path),
    do: path
  def json_path!(path),
    do: error!("expected `path` to be a list in json_extract_path/2, got: `#{inspect path}`")

  @doc """
  Called by escaper at runtime to verify that a value is not nil.
  """
  def not_nil!(nil) do
    raise ArgumentError, "comparison with nil is forbidden as it is unsafe. " <>
                         "If you want to check if a value is nil, use is_nil/1 instead"
  end
  def not_nil!(not_nil) do
    not_nil
  end

  @doc """
  Checks if the field is a valid interval at compilation time or
  delegate the check to runtime for interpolation.
  """
  def quoted_interval!({:^, _, [expr]}),
    do: quote(do: Ecto.Query.Builder.interval!(unquote(expr)))
  def quoted_interval!(other),
    do: interval!(other)

  @doc """
  Called by escaper at runtime to verify fragment keywords.
  """
  def fragment!(kw) do
    if Keyword.keyword?(kw) do
      kw
    else
      raise ArgumentError, bad_fragment_message(inspect(kw))
    end
  end

  @doc """
  Called by escaper at runtime to verify literal in fragments.
  """
  def literal!(literal) do
    if is_binary(literal) do
      literal
    else
      raise ArgumentError,
            "literal(^value) expects `value` to be a string, got `#{inspect(literal)}`"
    end
  end

  @doc """
  Called by escaper at runtime to verify that value is a valid interval.
  """
  @interval ~w(year month week day hour minute second millisecond microsecond)
  def interval!(interval) when interval in @interval,
    do: interval
  def interval!(other_string) when is_binary(other_string),
    do: error!("invalid interval: `#{inspect other_string}` (expected one of #{Enum.join(@interval, ", ")})")
  def interval!(not_string),
    do: error!("invalid interval: `#{inspect not_string}` (expected a string)")

  @doc """
  Negates the given number.
  """
  # TODO: Remove check when we depend on decimal v2.0
  if Code.ensure_loaded?(Decimal) and function_exported?(Decimal, :negate, 1) do
    def negate!(%Decimal{} = decimal), do: Decimal.negate(decimal)
  else
    def negate!(%Decimal{} = decimal), do: Decimal.minus(decimal)
  end

  def negate!(number) when is_number(number), do: -number

  @doc """
  Returns the type of an expression at build time.
  """
  @spec quoted_type(Macro.t, Keyword.t) :: quoted_type

  # Fields
  def quoted_type({{:., _, [{var, _, context}, field]}, _, []}, vars)
    when is_atom(var) and is_atom(context) and is_atom(field),
    do: {find_var!(var, vars), field}

  def quoted_type({:field, _, [{var, _, context}, field]}, vars)
    when is_atom(var) and is_atom(context) and is_atom(field),
    do: {find_var!(var, vars), field}

  # Unquoting code here means the second argument of field will
  # always be unquoted twice, one by the type checking and another
  # in the query itself. We are assuming this is not an issue
  # as the solution is somewhat complicated.
  def quoted_type({:field, _, [{var, _, context}, {:^, _, [code]}]}, vars)
    when is_atom(var) and is_atom(context),
    do: {find_var!(var, vars), code}

  # Interval
  def quoted_type({:datetime_add, _, [_, _, _]}, _vars), do: :naive_datetime
  def quoted_type({:date_add, _, [_, _, _]}, _vars), do: :date

  # Tagged
  def quoted_type({:<<>>, _, _}, _vars), do: :binary
  def quoted_type({:type, _, [_, type]}, _vars), do: type

  # Sigils
  def quoted_type({sigil, _, [_, []]}, _vars) when sigil in ~w(sigil_s sigil_S)a, do: :string
  def quoted_type({sigil, _, [_, []]}, _vars) when sigil in ~w(sigil_w sigil_W)a, do: {:array, :string}

  # Lists
  def quoted_type(list, vars) when is_list(list) do
    case list |> Enum.map(&quoted_type(&1, vars)) |> Enum.uniq() do
      [type] -> {:array, type}
      _ -> {:array, :any}
    end
  end

  # Negative numbers
  def quoted_type({:-, _, [number]}, _vars) when is_integer(number), do: :integer
  def quoted_type({:-, _, [number]}, _vars) when is_float(number), do: :float

  # Dynamic aggregates
  for {agg, arity} <- @dynamic_aggregates do
    args = 1..arity |> Enum.map(fn _ -> Macro.var(:_, __MODULE__) end) |> tl()

    def quoted_type({unquote(agg), _, [expr, unquote_splicing(args)]}, vars) do
      quoted_type(expr, vars)
    end
  end

  # Literals
  def quoted_type(literal, _vars) when is_float(literal),   do: :float
  def quoted_type(literal, _vars) when is_binary(literal),  do: :string
  def quoted_type(literal, _vars) when is_boolean(literal), do: :boolean
  def quoted_type(literal, _vars) when is_atom(literal) and not is_nil(literal), do: :atom
  def quoted_type(literal, _vars) when is_integer(literal), do: :integer

  # Tuples
  def quoted_type({left, right}, vars), do: quoted_type({:{}, [], [left, right]}, vars)
  def quoted_type({:{}, _, elems}, vars), do: {:tuple, Enum.map(elems, &quoted_type(&1, vars))}

  def quoted_type({name, _, args}, _vars) when is_atom(name) and is_list(args) do
    case call_type(name, length(args)) do
      {_in, out} -> out
      nil        -> :any
    end
  end

  def quoted_type(_, _vars), do: :any

  defp get_env({env, _}), do: env
  defp get_env(env), do: env

  @doc """
  Raises a query building error.
  """
  def error!(message) when is_binary(message) do
    {:current_stacktrace, [_|t]} = Process.info(self(), :current_stacktrace)

    t = Enum.drop_while t, fn
      {mod, _, _, _} ->
        String.starts_with?(Atom.to_string(mod), ["Elixir.Ecto.Query.", "Elixir.Enum"])
      _ ->
        false
    end

    reraise Ecto.Query.CompileError, [message: message], t
  end

  @doc """
  Counts the bindings in a query expression.

  ## Examples

      iex> count_binds(%Ecto.Query{joins: [1,2,3]})
      4

  """
  @spec count_binds(Ecto.Query.t) :: non_neg_integer
  def count_binds(%Query{joins: joins}) do
    1 + length(joins)
  end

  @doc """
  Bump interpolations by the length of parameters.
  """
  def bump_interpolations(expr, []), do: expr

  def bump_interpolations(expr, params) do
    len = length(params)

    Macro.prewalk(expr, fn
      {:^, meta, [counter]} when is_integer(counter) -> {:^, meta, [len + counter]}
      other -> other
    end)
  end

  @doc """
  Bump subqueries by the count of pre-existing subqueries.
  """
  def bump_subqueries(expr, []), do: expr

  def bump_subqueries(expr, subqueries) do
    len = length(subqueries)

    Macro.prewalk(expr, fn
      {:subquery, counter} -> {:subquery, len + counter}
      other -> other
    end)
  end

  @doc """
  Called by the select escaper at compile time and dynamic builder at runtime to track select aliases
  """
  def add_select_alias(aliases, name) do
    case aliases do
      %{^name => _} ->
        error! "the alias `#{inspect(name)}` has been specified more than once using `selected_as/2`"

      aliases ->
        Map.put(aliases, name, @select_alias_dummy_value)
    end
  end

  @doc """
  Applies a query at compilation time or at runtime.

  This function is responsible for checking if a given query is an
  `Ecto.Query` struct at compile time. If it is not it will act
  accordingly.

  If a query is available, it invokes the `apply` function in the
  given `module`, otherwise, it delegates the call to runtime.

  It is important to keep in mind the complexities introduced
  by this function. In particular, a %Query{} is a mixture of escaped
  and unescaped expressions which makes it impossible for this
  function to properly escape or unescape it at compile/runtime.
  For this reason, the apply function should be ready to handle
  arguments in both escaped and unescaped form.

  For example, take into account the `Builder.OrderBy`:

      select = %Ecto.Query.QueryExpr{expr: expr, file: env.file, line: env.line}
      Builder.apply_query(query, __MODULE__, [order_by], env)

  `expr` is already an escaped expression and we must not escape
  it again. However, it is wrapped in an Ecto.Query.QueryExpr,
  which must be escaped! Furthermore, the `apply/2` function
  in `Builder.OrderBy` very likely will inject the QueryExpr inside
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
  @spec apply_query(Macro.t, Macro.t, Macro.t, Macro.Env.t) :: Macro.t
  def apply_query(query, module, args, env) do
    case Macro.expand(query, env) |> unescape_query() do
      %Query{} = compiletime_query ->
        apply(module, :apply, [compiletime_query | args])
        |> escape_query()

      runtime_query ->
        quote do
          # Unquote the query before `module.apply()` for any binding variable.
          query = unquote(runtime_query)
          unquote(module).apply(query, unquote_splicing(args))
        end
    end
  end

  # Unescapes an `Ecto.Query` struct.
  @spec unescape_query(Macro.t) :: Query.t | Macro.t
  defp unescape_query({:%, _, [Query, {:%{}, _, list}]}) do
    struct(Query, list)
  end
  defp unescape_query({:%{}, _, list} = ast) do
    if List.keyfind(list, :__struct__, 0) == {:__struct__, Query} do
      Map.new(list)
    else
      ast
    end
  end
  defp unescape_query(other) do
    other
  end

  # Escapes an `Ecto.Query` and associated structs.
  @spec escape_query(Query.t) :: Macro.t
  defp escape_query(%Query{} = query), do: {:%{}, [], Map.to_list(query)}

  defp parse_access_get({{:., _, [Access, :get]}, _, [left, right]}, acc) do
    parse_access_get(left, [right | acc])
  end

  defp parse_access_get({{:., _, [{var, _, context}, field]}, _, []} = expr, acc)
       when is_atom(var) and is_atom(context) and is_atom(field) do
    {expr, acc}
  end
end
