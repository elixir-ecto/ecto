defmodule Ecto.Query.Builder.Join do
  @moduledoc false

  alias Ecto.Query.Builder
  alias Ecto.Query.JoinExpr

  @doc """
  Escapes a join expression (not including the `on` expression).

  It returns a tuple containing the binds, the on expression (if available)
  and the association expression.

  ## Examples

      iex> escape(quote(do: x in "foo"), [], __ENV__)
      {:x, {"foo", nil}, nil, %{}}

      iex> escape(quote(do: "foo"), [], __ENV__)
      {:_, {"foo", nil}, nil, %{}}

      iex> escape(quote(do: x in Sample), [], __ENV__)
      {:x, {nil, {:__aliases__, [alias: false], [:Sample]}}, nil, %{}}

      iex> escape(quote(do: x in {"foo", Sample}), [], __ENV__)
      {:x, {"foo", {:__aliases__, [alias: false], [:Sample]}}, nil, %{}}

      iex> escape(quote(do: x in {"foo", :sample}), [], __ENV__)
      {:x, {"foo", :sample}, nil, %{}}

      iex> escape(quote(do: c in assoc(p, :comments)), [p: 0], __ENV__)
      {:c, nil, {0, :comments}, %{}}

      iex> escape(quote(do: x in fragment("foo")), [], __ENV__)
      {:x, {:{}, [], [:fragment, [], [raw: "foo"]]}, nil, %{}}

  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: {[atom], Macro.t | nil, Macro.t | nil, %{}}
  def escape({:in, _, [{var, _, context}, expr]}, vars, env)
      when is_atom(var) and is_atom(context) do
    {_, expr, assoc, params} = escape(expr, vars, env)
    {var, expr, assoc, params}
  end

  def escape({:fragment, _, [_|_]} = expr, vars, env) do
    {expr, params} = Builder.escape(expr, :any, %{}, vars, env)
    {:_, expr, nil, params}
  end

  def escape({:__aliases__, _, _} = module, _vars, _env) do
    {:_, {nil, module}, nil, %{}}
  end

  def escape(string, _vars, _env) when is_binary(string) do
    {:_, {string, nil}, nil, %{}}
  end

  def escape({string, {:__aliases__, _, _} = module}, _vars, _env) when is_binary(string) do
    {:_, {string, module}, nil, %{}}
  end

  def escape({string, atom}, _vars, _env) when is_binary(string) and is_atom(atom) do
    {:_, {string, atom}, nil, %{}}
  end

  def escape({:assoc, _, [{var, _, context}, field]}, vars, _env)
      when is_atom(var) and is_atom(context) do
    var   = Builder.find_var!(var, vars)
    field = Builder.quoted_field!(field)
    {:_, nil, {var, field}, %{}}
  end

  def escape({:^, _, [expr]}, _vars, _env) do
    {:_, quote(do: Ecto.Query.Builder.Join.join!(unquote(expr))), nil, %{}}
  end

  def escape(join, _vars, _env) do
    Builder.error! "malformed join `#{Macro.to_string(join)}` in query expression"
  end

  @doc """
  Called at runtime to check dynamic joins.
  """
  def join!(expr) when is_atom(expr),
    do: {nil, expr}
  def join!(expr) when is_binary(expr),
    do: {expr, nil}
  def join!({source, module}) when is_binary(source) and is_atom(module),
    do: {source, module}
  def join!(expr) do
    raise ArgumentError,
      "expected join to be a string, atom or {string, atom}, got: `#{inspect expr}`"
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, atom, [Macro.t], Macro.t, Macro.t, Macro.t, Macro.Env.t) ::
              {Macro.t, Keyword.t, non_neg_integer | nil}
  def build(query, qual, binding, expr, on, count_bind, env) do
    binding = Builder.escape_binding(binding)
    {join_bind, join_expr, join_assoc, join_params} = escape(expr, binding, env)
    join_params = Builder.escape_params(join_params)

    qual = validate_qual(qual)
    count_setter = nil
    validate_bind(join_bind, binding)

    if join_bind != :_ and !count_bind do
      # If count_bind is not an integer, make it a variable.
      # The variable is the getter/setter storage.
      count_bind = quote(do: count_bind)
      count_setter = quote(do: unquote(count_bind) = Builder.count_binds(query))
    end

    if on && join_assoc do
      Builder.error! "cannot specify `on` on `#{qual}_join` when using association join, " <>
                     "add extra clauses with `where` instead"
    end

    binding = binding ++ [{join_bind, count_bind}]
    join_on = escape_on(on || true, binding, env)

    join =
      quote do
        %JoinExpr{qual: unquote(qual), source: unquote(join_expr),
                  on: unquote(join_on), assoc: unquote(join_assoc),
                  file: unquote(env.file), line: unquote(env.line),
                  params: unquote(join_params)}
      end

    {count_bind, quoted} =
      if is_integer(count_bind) do
        {count_bind + 1,
         Builder.apply_query(query, __MODULE__, [join], env)}
      else
        {quote(do: unquote(count_bind) + 1),
         quote do
           query = Ecto.Queryable.to_query(unquote(query))
           unquote(count_setter)
           %{query | joins: query.joins ++ [unquote(join)]}
         end}
      end

    {quoted, binding, count_bind}
  end

  def apply(query, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | joins: query.joins ++ [expr]}
  end

  defp escape_on(on, binding, env) do
    {on, params} = Builder.escape(on, :boolean, %{}, binding, env)
    params       = Builder.escape_params(params)

    quote do: %Ecto.Query.QueryExpr{
                expr: unquote(on),
                params: unquote(params),
                line: unquote(env.line),
                file: unquote(env.file)}
  end

  defp validate_qual(qual) when is_atom(qual) do
    qual!(qual)
  end

  defp validate_qual(qual) do
    quote(do: Ecto.Query.Builder.Join.qual!(unquote(qual)))
  end

  defp validate_bind(bind, all) do
    if bind != :_ and bind in all do
      Builder.error! "variable `#{bind}` is already defined in query"
    end
  end

  @qualifiers [:inner, :left, :right, :full]

  @doc """
  Called at runtime to check dynamic qualifier.
  """
  def qual!(qual) when qual in @qualifiers, do: qual
  def qual!(qual) do
    raise ArgumentError,
      "invalid join qualifier `#{inspect qual}`, accepted qualifiers are: " <>
      Enum.map_join(@qualifiers, ", ", &"`#{inspect &1}`")
  end
end
