defmodule Ecto.Query.BuilderUtil do
  @moduledoc false

  # Common functions for the query builder modules.

  # Smart escapes a query expression. Everything that is a query expression will
  # be escaped, foreign (elixir) expressions will not be escaped so that they
  # will be evaluated in their place. This means that everything foreign will be
  # inserted as-is into the query.

  # var.x - where var is bound
  def escape(expr, vars, join_var // nil)

  def escape({ { :., _, [{ var, _, context}, right] }, _, [] }, vars, join_var)
      when is_atom(var) and is_atom(context) do
    left_escaped = escape_var(var, vars, join_var)
    dot_escaped = { :{}, [], [:., [], [left_escaped, right]] }
    { :{}, [], [dot_escaped, [], []] }
  end

  # interpolation
  def escape({ :^, _, [arg] }, _vars, _join_var) do
    arg
  end

  def escape({ :binary, _, [arg] }, vars, join_var) do
    arg_escaped = escape(arg, vars, join_var)
    Ecto.Binary[value: arg_escaped]
  end

  # field macro
  def escape({ :field, _, [{ var, _, context }, field] }, vars, join_var)
      when is_atom(var) and is_atom(context) do
    escape_field(var, escape(field, vars, join_var), vars, join_var)
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

  def escape_var(var, vars, join_var // nil) do
    if var == join_var do
      # Get the variable bound in the join expression's actual position
      ix = quote do var!(count_binds, Ecto.Query) end
      { :{}, [], [:&, [], [ix]] }
    else
      ix = Enum.find_index(vars, &(&1 == var))
      if var != :_ and ix do
        { :{}, [], [:&, [], [ix]] }
      else
        raise Ecto.QueryError, reason: "unbound variable `#{var}` in query"
      end
    end
  end

  def escape_field(var, field, vars, join_var // nil) do
    left_escaped = escape_var(var, vars, join_var)
    dot_escaped = { :{}, [], [:., [], [left_escaped, field]] }
    { :{}, [], [dot_escaped, [], []] }
  end

  # Helpers used by all builders for optimizing the query at
  # runtime or compilation time. Currently they are in this
  # module but the plan is to extract them.

  alias Ecto.Query.Query

  def apply_query(query, module, args, env) do
    query = Macro.expand(query, env)
    case unescape(query) do
      Query[] = unescaped ->
        apply(module, :apply, [unescaped|args]) |> escape
      _ ->
        args = lc i inlist [query|args], do: escape(i)
        quote do
          unquote(module).apply(unquote_splicing(args))
        end
    end
  end

  def unescape({ :{}, _meta, [Query|_] = query }),
    do: list_to_tuple(query)
  def unescape(other),
    do: other

  def escape(Query[] = query),
    do: { :{}, [], tuple_to_list(query) }
  def escape(other),
    do: other
end
