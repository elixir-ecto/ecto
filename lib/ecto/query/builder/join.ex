defmodule Ecto.Query.Builder.Join do
  @moduledoc false

  alias Ecto.Query.Builder
  alias Ecto.Query.JoinExpr

  @doc """
  Escapes a join expression (not including the `on` expression).

  It returns a tuple containing the binds, the on expression (if available)
  and the association expression.

  ## Examples

      iex> escape(quote(do: x in "foo"), [])
      {:x, {"foo", nil}, nil}

      iex> escape(quote(do: "foo"), [])
      {nil, {"foo", nil}, nil}

      iex> escape(quote(do: x in Sample), [])
      {:x, {nil, {:__aliases__, [alias: false], [:Sample]}}, nil}

      iex> escape(quote(do: c in p.comments), [p: 0])
      {:c, nil, {0, :comments}}

      iex> escape(quote(do: c in p.comments()), [p: 0])
      {:c, nil, {0, :comments}}

      iex> escape(quote(do: c in field(p, :comments)), [p: 0])
      {:c, nil, {0, :comments}}

  """
  # TODO: Forbid the field(...) and p.comment syntax
  @spec escape(Macro.t, Keyword.t) :: {[atom], Macro.t | nil, Macro.t | nil}
  def escape({:in, _, [{var, _, context}, expr]}, vars)
      when is_atom(var) and is_atom(context) do
    {_, expr, assoc} = escape(expr, vars)
    {var, expr, assoc}
  end

  def escape({:__aliases__, _, _} = module, _vars) do
    {nil, {nil, module}, nil}
  end

  def escape(string, _vars) when is_binary(string) do
    {nil, {string, nil}, nil}
  end

  def escape({:field, _, [{var, _, context}, field]}, vars)
      when is_atom(var) and is_atom(context) do
    var   = find_var!(var, vars)
    field = Builder.quoted_field!(field)
    {[], nil, {var, field}}
  end

  def escape({{:., _, [{var, _, context}, field]}, _, []}, vars)
      when is_atom(var) and is_atom(context) and is_atom(field) do
    {[], nil, {find_var!(var, vars), field}}
  end

  def escape(join, _vars) do
    Builder.error! "malformed join `#{Macro.to_string(join)}` in query expression"
  end

  defp find_var!(var, vars) do
    vars[var] || Builder.error! "unbound variable `#{var}` in query"
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, atom, [Macro.t], Macro.t, Macro.t, Macro.t, Macro.Env.t) :: {Macro.t, Keyword.t, non_neg_integer | nil}
  def build(query, qual, binding, expr, on, count_bind, env) do
    binding = Builder.escape_binding(binding)
    {join_bind, join_expr, join_assoc} = escape(expr, binding)

    validate_qual(qual)
    validate_bind(join_bind, binding)

    if join_bind && !count_bind do
      # If count_bind is not an integer, make it a variable.
      # The variable is the getter/setter storage.
      count_bind = quote(do: count_bind)
      count_setter = quote(do: unquote(count_bind) = Builder.count_binds(query))
    end

    binding = binding ++ [{join_bind, count_bind}]
    join_on = escape_on(on || true, binding, env)

    join =
      quote do
        %JoinExpr{qual: unquote(qual), source: unquote(join_expr),
                  on: unquote(join_on), assoc: unquote(join_assoc),
                  file: unquote(env.file), line: unquote(env.line)}
      end

    if is_integer(count_bind) do
      count_bind = count_bind + 1
      quoted = Builder.apply_query(query, __MODULE__, [join], env)
    else
      count_bind = quote(do: unquote(count_bind) + 1)
      quoted =
        quote do
          query = Ecto.Queryable.to_query(unquote(query))
          unquote(count_setter)
          %{query | joins: query.joins ++ [unquote(join)]}
        end
      end

    {quoted, binding, count_bind}
  end

  def apply(query, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | joins: query.joins ++ [expr]}
  end

  defp escape_on(on, binding, env) do
    {on, params} = Builder.escape(on, :boolean, %{}, binding)
    params       = Builder.escape_params(params)

    quote do: %Ecto.Query.QueryExpr{
                expr: unquote(on),
                params: unquote(params),
                line: unquote(env.line),
                file: unquote(env.file)}
  end

  @qualifiers [:inner, :left, :right, :full]

  defp validate_qual(qual) when qual in @qualifiers, do: :ok
  defp validate_qual(qual) do
    Builder.error! "invalid join qualifier `#{inspect qual}`, accepted qualifiers are: " <>
                   Enum.map_join(@qualifiers, ", ", &"`#{inspect &1}`")
  end

  defp validate_bind(bind, all) do
    if bind && bind in all do
      Builder.error! "variable `#{bind}` is already defined in query"
    end
  end
end
