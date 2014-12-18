defmodule Ecto.Query.Builder do
  @moduledoc false

  alias Ecto.Query

  @type type :: :any | :integer | :float | :boolean | :string |
                :binary | :uuid | {:array, type} | :decimal |
                :datetime | :time | :date

  @doc """
  Smart escapes a query expression and extracts interpolated values in
  a map.

  Everything that is a query expression will be escaped, interpolated
  expressions (`^foo`) will be moved to a map unescaped and replaced
  with `^index` in the query where index is a number indexing into the
  map.
  """
  @spec escape(Macro.t, type, map(), Keyword.t) :: {Macro.t, %{}}
  def escape(expr, type, params, vars)

  # var.x - where var is bound
  def escape({{:., _, [{var, _, context}, right]}, _, []}, _type, params, vars)
      when is_atom(var) and is_atom(context) and is_atom(right) do
    left_escaped = escape_var(var, vars)
    dot_escaped  = {:{}, [], [:., [], [left_escaped, right]]}
    expr         = {:{}, [], [dot_escaped, [], []]}
    {expr, params}
  end

  # interpolation
  def escape({:^, _, [arg]}, _type, params, _vars) do
    index  = Map.size(params)
    params = Map.put(params, index, arg)
    expr   = {:{}, [], [:^, [], [index]]}
    {expr, params}
  end

  # tagged types
  def escape({:<<>>, _, _} = bin, _type, params, _vars) do
    expr = {:%, [], [Ecto.Query.Tagged, {:%{}, [], [value: bin, type: :binary]}]}
    {expr, params}
  end

  def escape({:uuid, _, [bin]}, _type, params, _vars) when is_binary(bin) do
    expr = {:%, [], [Ecto.Query.Tagged, {:%{}, [], [value: bin, type: :uuid]}]}
    {expr, params}
  end

  def escape({:uuid, _, [{:<<>>, _, _} = bin]}, _type, params, _vars) do
    expr = {:%, [], [Ecto.Query.Tagged, {:%{}, [], [value: bin, type: :uuid]}]}
    {expr, params}
  end

  # field macro
  def escape({:field, _, [{var, _, context}, field]}, _type, params, vars)
      when is_atom(var) and is_atom(context) do
    var = escape_var(var, vars)

    field = quoted_atom!(field)
    dot   = {:{}, [], [:., [], [var, field]]}
    expr  = {:{}, [], [dot, [], []]}

    {expr, params}
  end

  # fragments
  def escape({sigil, _, [{:<<>>, _, frags}, []]}, _type, params, vars) when sigil in ~w(sigil_f sigil_F)a do
    {frags, params} =
      Enum.map_reduce frags, params, fn
        frag, params when is_binary(frag) ->
          {frag, params}
        {:::, _, [{{:., _, [Kernel, :to_string]}, _, [frag]}, _]}, params ->
          escape(frag, :binary, params, vars)
      end

    {{:%, [], [Ecto.Query.Fragment, {:%{}, [], [parts: frags]}]},
      params}
  end

  # sigils
  def escape({name, _, _} = sigil, _type, params, _vars) when name in ~w(sigil_s sigil_S sigil_w sigil_W)a do
    {sigil, params}
  end

  # literals
  def escape(list, _type, params, vars) when is_list(list),
    do: Enum.map_reduce(list, params, &escape(&1, :any, &2, vars))
  def escape(literal, _type, params, _vars) when is_binary(literal),
    do: {literal, params}
  def escape(literal, _type, params, _vars) when is_boolean(literal),
    do: {literal, params}
  def escape(literal, _type, params, _vars) when is_number(literal),
    do: {literal, params}
  def escape(nil, _type, params, _vars),
    do: {nil, params}

  # comparison operators
  def escape({comp_op, meta, [left, right]}, _type, params, vars) when comp_op in ~w(== != < > <= >=)a do
    escape_call(comp_op, meta, [left, right], params, vars)
  end

  # boolean binary operator
  def escape({bool_op, meta, [left, right]}, _type, params, vars) when bool_op in ~w(and or)a do
    escape_call(bool_op, meta, [left, right], params, vars)
  end

  # boolean unary operator
  def escape({:not, meta, [single]}, _type, params, vars) do
    escape_call(:not, meta, [single], params, vars)
  end

  # in operator
  def escape({:in, meta, [left, right]}, _type, params, vars) do
    escape_call(:in, meta, [left, right], params, vars)
  end

  # Other functions - no type casting
  def escape({name, meta, args} = call, _type, params, vars) when is_atom(name) and is_list(args) do
    if valid_call?(name, length(args)) do
      escape_call(name, meta, args, params, vars)
    else
      raise Ecto.QueryError, reason: """
      `#{Macro.to_string(call)}` is not a valid query expression.

      * If you intended to call a database function, please check the documentation
        for Ecto.Query to see the supported database expressions

      * If you intended to call an Elixir function or introduce a value,
        you need to explicitly interpolate it with ^
      """
    end
  end

  # everything else is not allowed
  def escape({name, _, context} = var, _type, _params, _vars) when is_atom(name) and is_atom(context) do
    raise Ecto.QueryError, reason:
      "Variable `#{Macro.to_string(var)}` is not a valid query expression. " <>
      "Variables need to be explicitly interpolated in queries with ^"
  end

  def escape(other, _type, _params, _vars) do
    raise Ecto.QueryError, reason: "`#{Macro.to_string(other)}` is not a valid query expression"
  end

  defp valid_call?(agg, 1)  when agg in ~w(max count sum min avg)a, do: true
  defp valid_call?(like, 2) when like in ~w(like ilike)a, do: true
  defp valid_call?(:is_nil, 1), do: true
  defp valid_call?(_, _),       do: false

  defp escape_call(name, meta, args, params, vars) do
    {args, params} = Enum.map_reduce(args, params, &escape(&1, :any, &2, vars))
    expr = {:{}, [], [name, meta, args]}
    {expr, params}
  end

  @doc """
  Escape the params entries map.
  """
  def escape_params(map) do
    {:%{}, [], Map.to_list(map)}
  end

  @doc """
  Escapes a variable according to the given binds.

  A escaped variable is represented internally as `&0`, `&1` and
  so on.
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

  @doc """
  Checks the variable is a quoted atom at compilation time or
  delegate the check to runtime for interpolation.
  """
  def quoted_atom!({:^, _, [expr]}),
    do: quote(do: :"Elixir.Ecto.Query.Builder".atom!(unquote(expr)))
  def quoted_atom!(atom) when is_atom(atom),
    do: atom
  def quoted_atom!(other),
    do: raise(Ecto.QueryError, reason: "expected literal atom or interpolated value, got: `#{inspect other}`")

  @doc """
  Called by escaper at runtime to verify that value is an atom.
  """
  def atom!(atom) when is_atom(atom),
    do: atom
  def atom!(other),
    do: raise(Ecto.QueryError, reason: "expected atom, got: `#{inspect other}`")
end
