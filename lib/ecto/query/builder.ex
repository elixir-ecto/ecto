defmodule Ecto.Query.Builder do
  @moduledoc false

  alias Ecto.Query

  @typedoc """
  Quoted types store primitive types and types in the format
  {source, quoted}. The latter are handled directly in the planner,
  never forwarded to Ecto.Type.

  The Ecto.Type module concerns itself only with runtime types,
  which include all primitive types and custom user types. Also
  note custom user types do not show up during compilation time.
  """
  @type quoted_type :: Ecto.Type.primitive | {non_neg_integer, atom | Macro.t}

  @doc """
  Smart escapes a query expression and extracts interpolated values in
  a map.

  Everything that is a query expression will be escaped, interpolated
  expressions (`^foo`) will be moved to a map unescaped and replaced
  with `^index` in the query where index is a number indexing into the
  map.
  """
  @spec escape(Macro.t, quoted_type, map(), Keyword.t, Macro.Env.t) :: {Macro.t, %{}}
  def escape(expr, type, params, vars, env)

  # var.x - where var is bound
  def escape({{:., _, [{var, _, context}, field]}, _, []}, _type, params, vars, _env)
      when is_atom(var) and is_atom(context) and is_atom(field) do
    {escape_field(var, field, vars), params}
  end

  # field macro
  def escape({:field, _, [{var, _, context}, field]}, _type, params, vars, _env)
      when is_atom(var) and is_atom(context) do
    {escape_field(var, field, vars), params}
  end

  # param interpolation
  def escape({:^, _, [arg]}, type, params, _vars, _env) do
    index  = Map.size(params)
    params = Map.put(params, index, {arg, type})
    expr   = {:{}, [], [:^, [], [index]]}
    {expr, params}
  end

  # tagged types
  def escape({:type, _, [{:^, _, [arg]}, type]}, _type, params, vars, _env) do
    {type, escaped} = validate_type!(type, vars)
    index  = Map.size(params)
    params = Map.put(params, index, {arg, type})

    expr = {:{}, [], [:type, [], [{:{}, [], [:^, [], [index]]}, escaped]]}
    {expr, params}
  end

  # fragments
  def escape({:fragment, _, [query]}, _type, params, vars, env) when is_list(query) do
    {escaped, params} = Enum.map_reduce(query, params, &escape_fragment(&1, :any, &2, vars, env))

    {{:{}, [], [:fragment, [], [escaped]]}, params}
  end

  def escape({:fragment, _, [{:^, _, [var]} = _expr]}, _type, params, _vars, _env) do
    expr = quote do
      Ecto.Query.Builder.keyword!(unquote(var))
    end
    {{:{}, [], [:fragment, [], [expr]]}, params}
  end

  def escape({:fragment, _, [query|frags]}, _type, params, vars, env) do
    pieces = expand_and_split_binary(query, env)

    if length(pieces) != length(frags) + 1 do
      error! "fragment(...) expects extra arguments in the same amount of question marks in string"
    end

    {frags, params} = Enum.map_reduce(frags, params, &escape(&1, :any, &2, vars, env))
    {{:{}, [], [:fragment, [], merge_fragments(pieces, frags)]}, params}
  end

  # interval

  def escape({:from_now, meta, [count, interval]}, type, params, vars, env) do
    utc = quote do: ^DateTime.utc_now
    escape({:datetime_add, meta, [utc, count, interval]}, type, params, vars, env)
  end

  def escape({:ago, meta, [count, interval]}, type, params, vars, env) do
    utc = quote do: ^DateTime.utc_now
    count =
      case count do
        {:^, meta, [value]} ->
          negate = quote do: Ecto.Query.Builder.negate!(unquote(value))
          {:^, meta, [negate]}
        value ->
          {:-, [], [value]}
      end
    escape({:datetime_add, meta, [utc, count, interval]}, type, params, vars, env)
  end

  def escape({:datetime_add, _, [datetime, count, interval]} = expr, type, params, vars, env) do
    assert_type!(expr, type, :naive_datetime)
    # TODO: use escape once support for Ecto.DateTime is removed
    {datetime, params} = escape_datetime(datetime, params, vars, env)
    {count, interval, params} = escape_interval(count, interval, params, vars, env)
    {{:{}, [], [:datetime_add, [], [datetime, count, interval]]}, params}
  end

  def escape({:date_add, _, [date, count, interval]} = expr, type, params, vars, env) do
    assert_type!(expr, type, :date)
    # TODO: use escape once support for Ecto.Date is removed
    {date, params} = escape_date(date, params, vars, env)
    {count, interval, params} = escape_interval(count, interval, params, vars, env)
    {{:{}, [], [:date_add, [], [date, count, interval]]}, params}
  end

  # sigils
  def escape({name, _, [_, []]} = sigil, type, params, vars, _env)
      when name in ~w(sigil_s sigil_S sigil_w sigil_W)a do
    {literal(sigil, type, vars), params}
  end

  # lists
  def escape(list, {:array, type}, params, vars, env) when is_list(list),
    do: Enum.map_reduce(list, params, &escape(&1, type, &2, vars, env))
  def escape(list, _type, params, vars, env) when is_list(list),
    do: Enum.map_reduce(list, params, &escape(&1, :any, &2, vars, env))

  # literals
  def escape({:<<>>, _, args} = expr, type, params, vars, _env) do
    valid? = Enum.all?(args, fn
      {:::, _, [left, _]} -> is_integer(left) or is_binary(left)
      left -> is_integer(left) or is_binary(left)
    end)

    unless valid? do
      error! "`#{Macro.to_string(expr)}` is not a valid query expression. " <>
             "Only literal binaries and strings are allowed, " <>
             "dynamic values need to be explicitly interpolated in queries with ^"
    end

    {literal(expr, type, vars), params}
  end

  def escape({:-, _, [number]}, type, params, vars, _env) when is_number(number),
    do: {literal(-number, type, vars), params}
  def escape(number, type, params, vars, _env) when is_number(number),
    do: {literal(number, type, vars), params}
  def escape(binary, type, params, vars, _env) when is_binary(binary),
    do: {literal(binary, type, vars), params}
  def escape(boolean, type, params, vars, _env) when is_boolean(boolean),
    do: {literal(boolean, type, vars), params}
  def escape(nil, _type, params, _vars, _env),
    do: {nil, params}

  # comparison operators
  def escape({comp_op, _, [left, right]} = expr, type, params, vars, env) when comp_op in ~w(== != < > <= >=)a do
    assert_type!(expr, type, :boolean)

    if is_nil(left) or is_nil(right) do
      error! "comparison with nil is forbidden as it is unsafe. " <>
             "If you want to check if a value is nil, use is_nil/1 instead"
    end

    ltype = quoted_type(right, vars)
    rtype = quoted_type(left, vars)

    {left,  params} = escape(left, ltype, params, vars, env)
    {right, params} = escape(right, rtype, params, vars, env)
    {{:{}, [], [comp_op, [], [left, right]]}, params |> wrap_nil(left) |> wrap_nil(right)}
  end

  # in operator
  def escape({:in, _, [left, right]} = expr, type, params, vars, env)
      when is_list(right)
      when is_tuple(right) and elem(right, 0) in ~w(sigil_w sigil_W)a do
    assert_type!(expr, type, :boolean)

    {:array, ltype} = quoted_type(right, vars)
    rtype = {:array, quoted_type(left, vars)}

    {left,  params} = escape(left, ltype, params, vars, env)
    {right, params} = escape(right, rtype, params, vars, env)
    {{:{}, [], [:in, [], [left, right]]}, params}
  end

  def escape({:in, _, [left, right]} = expr, type, params, vars, env) do
    assert_type!(expr, type, :boolean)

    ltype = {:out, quoted_type(right, vars)}
    rtype = {:in, quoted_type(left, vars)}

    {left,  params} = escape(left, ltype, params, vars, env)
    {right, params} = escape(right, rtype, params, vars, env)

    # Remove any type wrapper from the right side
    right =
      case right do
        {:{}, [], [:type, [], [right, _]]} -> right
        _ -> right
      end

    {{:{}, [], [:in, [], [left, right]]}, params}
  end

  def escape({:count, _, [arg, :distinct]}, type, params, vars, env) do
    {arg, params} = escape(arg, type, params, vars, env)
    expr = {:{}, [], [:count, [], [arg, :distinct]]}
    {expr, params}
  end

  def escape({op, _, _}, _type, _params, _vars, _env) when op in ~w(|| && !)a do
    error! "short-circuit operators are not supported: `#{op}`. " <>
           "Instead use boolean operators: `and`, `or`, and `not`"
  end

  # Other functions - no type casting
  def escape({name, _, args} = expr, type, params, vars, env) when is_atom(name) and is_list(args) do
    case call_type(name, length(args)) do
      {in_type, out_type} ->
        assert_type!(expr, type, out_type)
        escape_call(expr, in_type, params, vars, env)
      nil ->
        try_expansion(expr, type, params, vars, env)
    end
  end

  # Vars are not allowed
  def escape({name, _, context} = var, _type, _params, _vars, _env) when is_atom(name) and is_atom(context) do
    error! "variable `#{Macro.to_string(var)}` is not a valid query expression. " <>
           "Variables need to be explicitly interpolated in queries with ^"
  end

  # Everything else is not allowed
  def escape(other, _type, _params, _vars, _env) do
    error! "`#{Macro.to_string(other)}` is not a valid query expression"
  end

  defp wrap_nil(params, {:{}, _, [:^, _, [ix]]}) do
    Map.update!(params, ix, fn {val, type} ->
      quote do
        {Ecto.Query.Builder.not_nil!(unquote(val)), unquote(type)}
      end
    end)
  end
  defp wrap_nil(params, _other) do
    params
  end

  defp expand_and_split_binary(query, env) do
    case Macro.expand(query, env) do
      binary when is_binary(binary) ->
        split_binary(binary, "")
      _ ->
        error! "fragment(...) expects the first argument to be a string for SQL fragments, " <>
               "a keyword list, or an interpolated value, got: `#{Macro.to_string(query)}`"
    end
  end

  defp split_binary(<<>>, consumed),
    do: [consumed]
  defp split_binary(<<??, rest :: binary >>, consumed),
    do: [consumed | split_binary(rest, "")]
  defp split_binary(<<?\\, ??, rest :: binary >>, consumed),
    do: split_binary(rest, consumed <> <<??>>)
  defp split_binary(<<first :: utf8, rest :: binary>>, consumed),
    do: split_binary(rest, consumed <> <<first :: utf8>>)

  defp escape_call({name, _, args}, type, params, vars, env) do
    {args, params} = Enum.map_reduce(args, params, &escape(&1, type, &2, vars, env))
    expr = {:{}, [], [name, [], args]}
    {expr, params}
  end

  defp escape_field(var, field, vars) do
    var   = escape_var(var, vars)
    field = quoted_field!(field)
    dot   = {:{}, [], [:., [], [var, field]]}
    {:{}, [], [dot, [], []]}
  end

  defp escape_interval(count, interval, params, vars, env) do
    type =
      cond do
        is_float(count)   -> :float
        is_integer(count) -> :integer
        true              -> :decimal
      end

    {count, params} = escape(count, type, params, vars, env)
    {count, quoted_interval!(interval), params}
  end

  defp escape_fragment({key, [{_, _}|_] = exprs}, type, params, vars, env) when is_atom(key) do
    {escaped, params} = Enum.map_reduce(exprs, params, &escape_fragment(&1, type, &2, vars, env))
    {{key, escaped}, params}
  end

  defp escape_fragment({key, expr}, type, params, vars, env) when is_atom(key) do
    {escaped, params} = escape(expr, type, params, vars, env)
    {{key, escaped}, params}
  end

  defp escape_fragment({key, _expr}, _type, _params, _vars, _env) do
    error! "fragment(...) with keywords accepts only atoms as keys, got `#{Macro.to_string(key)}`"
  end

  defp escape_datetime({:^, meta, [expr]}, params, vars, env) do
    expr = quote do: Ecto.Query.Builder.cast_datetime!(unquote(expr))
    escape({:^, meta, [expr]}, :naive_datetime, params, vars, env)
  end
  defp escape_datetime(expr, params, vars, env) do
    escape(expr, :naive_datetime, params, vars, env)
  end

  defp escape_date({:^, meta, [expr]}, params, vars, env) do
    expr = quote do: Ecto.Query.Builder.cast_date!(unquote(expr))
    escape({:^, meta, [expr]}, :date, params, vars, env)
  end
  defp escape_date(expr, params, vars, env) do
    escape(expr, :date, params, vars, env)
  end

  defp merge_fragments([h1|t1], [h2|t2]),
    do: [{:raw, h1}, {:expr, h2}|merge_fragments(t1, t2)]
  defp merge_fragments([h1], []),
    do: [{:raw, h1}]

  defp call_type(agg, 1)  when agg in ~w(avg count max min sum)a, do: {:any, :any}
  defp call_type(comp, 2) when comp in ~w(== != < > <= >=)a,      do: {:any, :boolean}
  defp call_type(like, 2) when like in ~w(like ilike)a,           do: {:string, :boolean}
  defp call_type(bool, 2) when bool in ~w(and or)a,               do: {:boolean, :boolean}
  defp call_type(:not, 1),                                        do: {:boolean, :boolean}
  defp call_type(:is_nil, 1),                                     do: {:any, :boolean}
  defp call_type(_, _),                                           do: nil

  defp assert_type!(_expr, {int, _field}, _actual) when is_integer(int) do
    :ok
  end

  defp assert_type!(expr, type, actual) do
    if Ecto.Type.match?(type, actual) do
      :ok
    else
      error! "expression `#{Macro.to_string(expr)}` does not type check. " <>
             "It returns a value of type #{inspect actual} but a value of " <>
             "type #{inspect type} is expected"
    end
  end

  defp validate_type!({composite, type}, vars) do
    {type, escaped} = validate_type!(type, vars)
    {{composite, type}, {composite, escaped}}
  end

  defp validate_type!({:^, _, [type]}, _vars),
    do: {type, type}
  defp validate_type!({:__aliases__, _, _} = type, _vars),
    do: {type, type}
  defp validate_type!(type, _vars) when is_atom(type),
    do: {type, type}
  defp validate_type!({{:., _, [{var, _, context}, field]}, _, []}, vars)
    when is_atom(var) and is_atom(context) and is_atom(field),
    do: {{find_var!(var, vars), field}, escape_field(var, field, vars)}
  defp validate_type!({:field, _, [{var, _, context}, field]}, vars)
    when is_atom(var) and is_atom(context) and is_atom(field),
    do: {{find_var!(var, vars), field}, escape_field(var, field, vars)}

  defp validate_type!(type, _vars) do
    error! "type/2 expects an alias, atom or source.field as second argument, got: `#{Macro.to_string(type)}`"
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
  Escape the params entries map.
  """
  @spec escape_params(map()) :: Macro.t
  def escape_params(map) do
    Map.values(map)
  end

  @doc """
  Escapes a variable according to the given binds.

  A escaped variable is represented internally as
  `&0`, `&1` and so on.
  """
  @spec escape_var(atom, Keyword.t) :: Macro.t | no_return
  def escape_var(var, vars) do
    {:{}, [], [:&, [], [find_var!(var, vars)]]}
  end

  @doc """
  Escapes a list of bindings as a list of atoms.

  Only variables or `{:atom, value}` tuples are allowed in the `bindings` list,
  otherwise an `Ecto.Query.CompileError` is raised.

  ## Examples

      iex> escape_binding(%Ecto.Query{}, quote do: [x, y, z])
      {%Ecto.Query{}, [x: 0, y: 1, z: 2]}

      iex> escape_binding(%Ecto.Query{}, quote do: [x: 0, z: 2])
      {%Ecto.Query{}, [x: 0, z: 2]}

      iex> escape_binding(%Ecto.Query{}, quote do: [x, y, x])
      ** (Ecto.Query.CompileError) variable `x` is bound twice

      iex> escape_binding(%Ecto.Query{}, quote do: [a, b, :foo])
      ** (Ecto.Query.CompileError) binding list should contain only variables, got: :foo

  """
  @spec escape_binding(Macro.t | Ecto.Query.t, list) :: {Macro.t | Ecto.Query.t, Keyword.t}
  def escape_binding(query, binding) when is_list(binding) do
    vars = binding |> Enum.with_index |> Enum.map(&escape_bind(&1))
    assert_no_dup_binding!(vars)
    case Enum.split_while(vars, & elem(&1, 0) != :...) do
      {vars, []} ->
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
          |> Enum.map(fn {{k, _}, count} -> {k, quote(do: escape_count + unquote(count))} end)
        {query, vars ++ tail}
    end
  end
  def escape_binding(_query, bind) do
    error! "binding should be list of variables, got: #{Macro.to_string(bind)}"
  end

  defp assert_no_dup_binding!(vars) do
    bound_vars = vars |> Keyword.keys |> Enum.filter(& &1 != :_)
    case bound_vars -- Enum.uniq(bound_vars) do
      []  -> :ok
      dup -> error! "variable `#{hd dup}` is bound twice"
    end
  end

  defp escape_bind({{var, _} = tuple, _}) when is_atom(var),
    do: tuple
  defp escape_bind({{var, _, context}, ix}) when is_atom(var) and is_atom(context),
    do: {var, ix}
  defp escape_bind({bind, _ix}),
    do: error!("binding list should contain only variables, got: #{Macro.to_string(bind)}")

  defp try_expansion(expr, type, params, vars, env) do
    case Macro.expand(expr, env) do
      ^expr ->
        error! """
        `#{Macro.to_string(expr)}` is not a valid query expression.

        * If you intended to call a database function, please check the documentation
          for Ecto.Query to see the supported database expressions

        * If you intended to call an Elixir function or introduce a value,
          you need to explicitly interpolate it with ^
        """
      expanded ->
        escape(expanded, type, params, vars, env)
    end
  end

  @doc """
  Finds the index value for the given var in vars or raises.
  """
  def find_var!(var, vars) do
    vars[var] || error! "unbound variable `#{var}` in query"
  end

  @doc """
  Checks if the field is an atom at compilation time or
  delegate the check to runtime for interpolation.
  """
  def quoted_field!({:^, _, [expr]}),
    do: quote(do: Ecto.Query.Builder.field!(unquote(expr)))
  def quoted_field!(atom) when is_atom(atom),
    do: atom
  def quoted_field!(other),
    do: error!("expected literal atom or interpolated value in field/2, got: `#{inspect other}`")

  @doc """
  Called by escaper at runtime to verify that value is an atom.
  """
  def field!(atom) when is_atom(atom),
    do: atom
  def field!(other),
    do: error!("expected atom in field/2, got: `#{inspect other}`")

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
  Called by escaper at runtime to verify keywords.
  """
  def keyword!(kw) do
    unless Keyword.keyword?(kw) do
      raise ArgumentError, "to prevent sql injection, only a keyword list may be interpolated " <>
                           "as the first argument to `fragment/1` with the `^` operator, got `#{inspect kw}`"
    end

    kw
  end

  @doc """
  Called by escaper at runtime to verify that value is an atom.
  """
  @interval ~w(year month week day hour minute second millisecond microsecond)
  def interval!(interval) when interval in @interval,
    do: interval
  def interval!(other),
    do: error!("invalid interval: `#{inspect other}` (expected one of #{Enum.join(@interval, ", ")})")

  @doc """
  Called by escaper at runtime to cast Ecto.DateTime to :naive_datetime.
  """
  def cast_datetime!(%Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec, usec: usec}) do
    {:ok, value} = NaiveDateTime.new(year, month, day, hour, min, sec, {usec, 6})
    value
  end
  def cast_datetime!(value),
    do: value

  @doc """
  Called by escaper at runtime to cast Ecto.Date to :date.
  """
  def cast_date!(%Ecto.Date{year: year, month: month, day: day}) do
    {:ok, value} = Date.new(year, month, day)
    value
  end
  def cast_date!(value),
    do: value

  @doc """
  Negates the given number.
  """
  def negate!(%Decimal{} = decimal) do
    Decimal.minus(decimal)
  end
  def negate!(number) when is_number(number) do
    -number
  end

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
  def quoted_type({:datetime_add, _, [_, _, __]}, _vars), do: :naive_datetime
  def quoted_type({:date_add, _, [_, _, __]}, _vars), do: :date

  # Tagged
  def quoted_type({:<<>>, _, _}, _vars), do: :binary
  def quoted_type({:type, _, [_, type]}, _vars), do: type

  # Sigils
  def quoted_type({sigil, _, [_, []]}, _vars) when sigil in ~w(sigil_s sigil_S)a, do: :string
  def quoted_type({sigil, _, [_, []]}, _vars) when sigil in ~w(sigil_w sigil_W)a, do: {:array, :string}

  # Lists
  def quoted_type(list, vars) when is_list(list) do
    case Enum.uniq(Enum.map(list, &quoted_type(&1, vars))) do
      [type] -> {:array, type}
      _      -> {:array, :any}
    end
  end

  # Negative numbers
  def quoted_type({:-, _, [number]}, _vars) when is_integer(number), do: :integer
  def quoted_type({:-, _, [number]}, _vars) when is_float(number), do: :float

  # Aggregates
  def quoted_type({:count, _, [_, _]}, _vars), do: :integer
  def quoted_type({:count, _, [_]}, _vars), do: :integer
  def quoted_type({agg, _, [_]}, _vars) when agg in [:avg, :sum], do: :any # TODO: Support the number type
  def quoted_type({agg, _, [expr]}, vars) when agg in [:max, :min, :sum] do
    quoted_type(expr, vars)
  end

  # Literals
  def quoted_type(literal, _vars) when is_float(literal),   do: :float
  def quoted_type(literal, _vars) when is_binary(literal),  do: :string
  def quoted_type(literal, _vars) when is_boolean(literal), do: :boolean
  def quoted_type(literal, _vars) when is_integer(literal), do: :integer

  def quoted_type({name, _, args}, _vars) when is_atom(name) and is_list(args) do
    case call_type(name, length(args)) do
      {_in, out} -> out
      nil        -> :any
    end
  end

  def quoted_type(_, _vars), do: :any

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
  Applies a query at compilation time or at runtime.

  This function is responsible for checking if a given query is an
  `Ecto.Query` struct at compile time. If it is not it will act
  accordingly.

  If a query is available, it invokes the `apply` function in the
  given `module`, otherwise, it delegates the call to runtime.

  It is important to keep in mind the complexities introduced
  by this function. In particular, a %Query{} is mixture of escaped
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
  def apply_query(query, module, args, env) do
    query = Macro.expand(query, env)
    args  = for i <- args, do: escape_query(i)
    case unescape_query(query) do
      %Query{} = unescaped ->
        apply(module, :apply, [unescaped|args]) |> escape_query
      _ ->
        quote do
          query = unquote(query) # Unquote the query for any binding variable
          unquote(module).apply(query, unquote_splicing(args))
        end
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
end
