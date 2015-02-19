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
  def escape({{:., _, [{var, _, context}, field]}, _, []}, type, params, vars, _env)
      when is_atom(var) and is_atom(context) and is_atom(field) do
    var  = escape_var(var, vars)
    dot  = {:{}, [], [:., [], [var, field]]}
    expr = {:{}, [], [dot, field_meta(type), []]}
    {expr, params}
  end

  # field macro
  def escape({:field, _, [{var, _, context}, field]}, type, params, vars, _env)
      when is_atom(var) and is_atom(context) do
    var   = escape_var(var, vars)
    field = quoted_field!(field)
    dot   = {:{}, [], [:., [], [var, field]]}
    expr  = {:{}, [], [dot, field_meta(type), []]}
    {expr, params}
  end

  # param interpolation
  def escape({:^, _, [arg]}, type, params, _vars, _env) do
    index  = Map.size(params)
    params = Map.put(params, index, {arg, type})
    expr   = {:{}, [], [:^, [], [index]]}
    {expr, params}
  end

  # tagged types
  def escape({:type, _, [{:^, _, [arg]}, tag]}, _type, params, _vars, _env) do
    index  = Map.size(params)
    params = Map.put(params, index, {arg, tag})

    map  = [value: {:{}, [], [:^, [], [index]]}, type: validate_type!(tag), tag: tag]
    expr = {:%, [], [Ecto.Query.Tagged, {:%{}, [], map}]}

    {expr, params}
  end

  # fragments
  def escape({:fragment, meta, [query|frags]}, _type, params, vars, env) do
    unless is_binary(query) do
      error! "fragment(...) expects the first argument to be a string, got: `#{Macro.to_string(query)}`"
    end

    pieces = String.split(query, "?")

    if length(pieces) != length(frags) + 1 do
      error! "fragment(...) expects extra arguments in the same amount of question marks in string"
    end

    {frags, params} = Enum.map_reduce(frags, params, &escape(&1, :any, &2, vars, env))
    {{:{}, [], [:fragment, meta, merge_fragments(pieces, frags)]}, params}
  end

  # sigils
  def escape({name, _, [_, _]} = sigil, _type, params, _vars, _env)
      when name in ~w(sigil_s sigil_S sigil_w sigil_W)a do
    {sigil, params}
  end

  # lists
  def escape(list, {:array, type}, params, vars, env) when is_list(list),
    do: Enum.map_reduce(list, params, &escape(&1, type, &2, vars, env))
  def escape(list, _type, params, vars, env) when is_list(list),
    do: Enum.map_reduce(list, params, &escape(&1, :any, &2, vars, env))

  # literals
  def escape(literal, _type, params, _vars, _env) when is_binary(literal),
    do: {literal, params}
  def escape(literal, _type, params, _vars, _env) when is_boolean(literal),
    do: {literal, params}
  def escape(literal, _type, params, _vars, _env) when is_number(literal),
    do: {literal, params}
  def escape(nil, _type, params, _vars, _env),
    do: {nil, params}

  # comparison operators
  def escape({comp_op, meta, [left, right]} = expr, type, params, vars, env) when comp_op in ~w(== != < > <= >=)a do
    assert_type!(expr, type, :boolean)

    if is_nil(left) or is_nil(right) do
      error! "comparison with nil is forbidden as it always evaluates to false. " <>
             "If you want to check if a value is (not) nil, use is_nil/1 instead"
    end

    ltype = quoted_type(right, vars)
    rtype = quoted_type(left, vars)

    {left,  params} = escape(left, ltype, params, vars, env)
    {right, params} = escape(right, rtype, params, vars, env)
    {{:{}, [], [comp_op, meta, [left, right]]}, params}
  end

  # in operator
  def escape({:in, meta, [left, right]} = expr, type, params, vars, env) when is_list(right) do
    assert_type!(expr, type, :boolean)

    {:array, ltype} = quoted_type(right, vars)
    rtype = {:array, quoted_type(left, vars)}

    {left,  params} = escape(left, ltype, params, vars, env)
    {right, params} = escape(right, rtype, params, vars, env)
    {{:{}, [], [:in, meta, [left, right]]}, params}
  end

  def escape({:in, meta, [left, {:^, _, _} = right]} = expr, type, params, vars, env) do
    assert_type!(expr, type, :boolean)

    ltype = :any
    rtype = {:in, quoted_type(left, vars)}

    {left,  params} = escape(left, ltype, params, vars, env)
    {right, params} = escape(right, rtype, params, vars, env)
    {{:{}, [], [:in, meta, [left, right]]}, params}
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

  defp escape_call({name, meta, args}, type, params, vars, env) do
    {args, params} = Enum.map_reduce(args, params, &escape(&1, type, &2, vars, env))
    expr = {:{}, [], [name, meta, args]}
    {expr, params}
  end

  # We don't embed the type in the field metadata if the type
  # is :any or if the type requires checking another field.
  #
  # Ecto concerns itself with type casting of concrete types
  # for security purposes. Comparing a field with another is
  # left to the database.

  defp merge_fragments([h1|t1], [h2|t2]),
    do: [h1, h2|merge_fragments(t1, t2)]
  defp merge_fragments([h1], []),
    do: [h1]

  defp field_meta(type) do
    type = extract_primitive_type(type)
    if type != :any, do: [ecto_type: type], else: []
  end

  defp call_type(agg, 1)  when agg in ~w(max count sum min avg)a, do: {:any, :any}
  defp call_type(comp, 2) when comp in ~w(== != < > <= >=)a,      do: {:any, :boolean}
  defp call_type(like, 2) when like in ~w(like ilike)a,           do: {:string, :boolean}
  defp call_type(bool, 2) when bool in ~w(and or)a,               do: {:boolean, :boolean}
  defp call_type(:not, 1),                                        do: {:boolean, :boolean}
  defp call_type(:is_nil, 1),                                     do: {:any, :boolean}
  defp call_type(:in, 2),                                         do: {:any, :boolean}
  defp call_type(_, _),                                           do: nil

  defp assert_type!(expr, type, actual) do
    if Ecto.Type.match?(type, actual) do
      :ok
    else
      error! "expression `#{Macro.to_string(expr)}` does not type check. " <>
             "It returns a value of type #{inspect actual} but a value of " <>
             "type #{inspect type} is expected"
    end
  end

  defp validate_type!({:array, {:__aliases__, _, _}} = type) do
    quote do: Ecto.Type.type(unquote(type))
  end
  defp validate_type!({:array, atom} = type) when is_atom(atom) do
    quote do: Ecto.Type.type(unquote(type))
  end
  defp validate_type!({:__aliases__, _, _} = type) do
    quote do: Ecto.Type.type(unquote(type))
  end
  defp validate_type!(type) when is_atom(type) do
    quote do: Ecto.Type.type(unquote(type))
  end
  defp validate_type!(type) do
    error! "type/2 expects an atom or alias as second argument, got: `#{Macro.to_string(type)}"
  end

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

      iex> escape_binding(quote do: [x, y, z])
      [x: 0, y: 1, z: 2]

      iex> escape_binding(quote do: [x: 0, z: 2])
      [x: 0, z: 2]

      iex> escape_binding(quote do: [x, y, x])
      ** (Ecto.Query.CompileError) variable `x` is bound twice

      iex> escape_binding(quote do: [a, b, :foo])
      ** (Ecto.Query.CompileError) binding list should contain only variables, got: :foo

  """
  @spec escape_binding(list) :: Keyword.t
  def escape_binding(binding) when is_list(binding) do
    vars       = binding |> Enum.with_index |> Enum.map(&escape_bind(&1))
    bound_vars = vars |> Keyword.keys |> Enum.filter(&(&1 != :_))
    dup_vars   = bound_vars -- Enum.uniq(bound_vars)

    unless dup_vars == [] do
      error! "variable `#{hd dup_vars}` is bound twice"
    end

    vars
  end

  def escape_binding(bind) do
    error! "binding should be list of variables, got: #{Macro.to_string(bind)}"
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
  Returns the primitive type of an expression at build time.
  """
  @spec primitive_type(Macro.t, Keyword.t) :: quoted_type
  def primitive_type(expr, vars) do
    extract_primitive_type quoted_type(expr, vars)
  end

  defp extract_primitive_type({composite, _} = type) when is_atom(composite), do: type
  defp extract_primitive_type(type) when is_atom(type), do: type
  defp extract_primitive_type(_), do: :any

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

  # Tagged
  def quoted_type({:<<>>, _, _}, _vars), do: :binary
  def quoted_type({:uuid, _, [_]}, _vars), do: :uuid
  def quoted_type({:type, _, [_, type]}, _vars), do: type

  # Sigils
  def quoted_type({sigil, _, _}, _vars) when sigil in ~w(sigil_s sigil_S)a, do: :string
  def quoted_type({sigil, _, _}, _vars) when sigil in ~w(sigil_w sigil_W)a, do: {:array, :string}

  # Lists
  def quoted_type(list, vars) when is_list(list) do
    case Enum.uniq(Enum.map(list, &quoted_type(&1, vars))) do
      [type] -> {:array, type}
      _      -> {:array, :any}
    end
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
    {:current_stacktrace, [_|t]} = Process.info(self, :current_stacktrace)

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
      3

      iex> count_binds(%Ecto.Query{from: 0, joins: [1,2]})
      3

  """
  @spec count_binds(Ecto.Query.t) :: non_neg_integer
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

  For example, take into account the `Builder.Select`:

      select = %Ecto.Query.QueryExpr{expr: expr, file: env.file, line: env.line}
      Builder.apply_query(query, __MODULE__, [select], env)

  `expr` is already an escaped expression and we must not escape
  it again. However, it is wrapped in an Ecto.Query.QueryExpr,
  which must be escaped! Furthermore, the `apply/2` function
  in `Builder.Select` very likely will inject the QueryExpr inside
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
end
