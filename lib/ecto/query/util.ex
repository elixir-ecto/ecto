defmodule Ecto.Query.Util do
  @moduledoc """
  This module provide utility functions on queries.
  """

  alias Ecto.Queryable
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Query.AssocJoinExpr

  @doc """
  Validates the query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate(query, query_apis, opts // []) do
    Ecto.Query.Validator.validate(query, query_apis, opts)
  end

  @doc """
  Validates an update query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate_update(query, query_apis, values) do
    Ecto.Query.Validator.validate_update(query, query_apis, values)
  end

  @doc """
  Validates a delete query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate_delete(query, query_apis) do
    Ecto.Query.Validator.validate_delete(query, query_apis)
  end

  @doc """
  Validates a get query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate_get(query, query_apis) do
    Ecto.Query.Validator.validate_get(query, query_apis)
  end

  @doc """
  Normalizes the query. Should be called before validation and compilation by
  the query adapter.
  """
  def normalize(query, opts // []) do
    Ecto.Query.Normalizer.normalize(query, opts)
  end

  @doc """
  Look up a model with a variable.
  """
  def find_model(models, { :&, _, [ix] }) when is_tuple(models) do
    elem(models, ix)
  end

  def find_model(models, { :&, _, [ix] }) when is_list(models) do
    Enum.at(models, ix)
  end

  @doc """
  Look up the expression where the variable was bound.
  """
  def find_expr(Query[from: from], { :&, _, [0] }) do
    from
  end

  def find_expr(Query[joins: joins], { :&, _, [ix] }) do
    Enum.at(joins, ix - 1)
  end

  # Merges a Queryable with a query expression
  @doc false
  def merge(queryable, type, expr) do
    query = Query[] = Queryable.to_query(queryable)

    if type == :on do
      merge_on(query, expr)
    else
      check_merge(query, Query.new([{ type, expr }]))

      case type do
        :from     -> query.from(expr)
        :join     -> query.update_joins(&(&1 ++ [expr]))
        :where    -> query.update_wheres(&(&1 ++ [expr]))
        :select   -> query.select(expr)
        :order_by -> query.update_order_bys(&(&1 ++ [expr]))
        :limit    -> query.limit(expr)
        :offset   -> query.offset(expr)
        :group_by -> query.update_group_bys(&(&1 ++ [expr]))
        :having   -> query.update_havings(&(&1 ++ [expr]))
        :preload  -> query.update_preloads(&(&1 ++ [expr]))
      end
    end
  end

  @doc false
  def merge_on(Query[joins: joins] = query, expr) do
    case Enum.split(joins, -1) do
      { joins, [JoinExpr[] = join] } ->
        joins = joins ++ [join.on(expr)]
        query.joins(joins)
      { _, [AssocJoinExpr[]] } ->
        raise Ecto.InvalidQuery, reason: "an `on` query expression cannot follow an assocation join"
      _ ->
        raise Ecto.InvalidQuery, reason: "an `on` query expression must follow a `join`"
    end
  end

  # Count the number of entities on the query
  @doc false
  def count_entities(queryable) do
    Query[from: from, joins: joins] = Queryable.to_query(queryable)
    count = if from, do: 1, else: 0
    count + length(joins)
  end

  # Converts list of variables to list of atoms
  @doc false
  def escape_binding(binding) when is_list(binding) do
    vars = Enum.map(binding, &escape_var(&1))

    bound_vars = Enum.filter(vars, &(&1 != :_))
    dup_vars = bound_vars -- Enum.uniq(bound_vars)
    unless dup_vars == [] do
      raise Ecto.InvalidQuery, reason: "variable `#{hd dup_vars}` is already defined in query"
    end

    vars
  end

  def escape_binding(_) do
    raise Ecto.InvalidQuery, reason: "binding should be list of variables"
  end

  # Converts internal type format to "typespec" format
  @doc false
  def type_to_ast({ type, inner }), do: { type, [], [type_to_ast(inner)] }
  def type_to_ast(type) when is_atom(type), do: { type, [], nil }

  # Takes an elixir value an returns its ecto type
  @doc false
  def value_to_type(nil), do: { :ok, nil }
  def value_to_type(value) when is_boolean(value), do: { :ok, :boolean }
  def value_to_type(value) when is_binary(value), do: { :ok, :string }
  def value_to_type(value) when is_integer(value), do: { :ok, :integer }
  def value_to_type(value) when is_float(value), do: { :ok, :float }

  def value_to_type(Ecto.DateTime[] = dt) do
    valid = is_integer(dt.year) and is_integer(dt.month) and is_integer(dt.day) and
            is_integer(dt.hour) and is_integer(dt.min)   and is_integer(dt.sec)

    if valid do
      { :ok, :datetime }
    else
      { :error, "all datetime elements has to be of integer type" }
    end
  end

  def value_to_type(Ecto.Interval[] = dt) do
    valid = is_integer(dt.year) and is_integer(dt.month) and is_integer(dt.day) and
            is_integer(dt.hour) and is_integer(dt.min)   and is_integer(dt.sec)

    if valid do
      { :ok, :interval }
    else
      { :error, "all interval elements has to be of integer type" }
    end
  end

  def value_to_type(list) when is_list(list) do
    types = Enum.map(list, &value_to_type/1)

    case types do
      [] ->
        { :ok, { :list, :any } }
      [type|rest] ->
        if Enum.all?(rest, &type_eq?(type, &1)) do
          { :ok, { :list, type } }
        else
          { :error, "all elements in list has to be of same type" }
        end
    end
  end

  def value_to_type(value), do: { :error, "`unknown type of value `#{inspect value}`" }

  # Returns true if the two types are considered equal by the type system
  @doc false
  def type_eq?(_, :any), do: true
  def type_eq?(:any, _), do: true
  def type_eq?({ outer, inner1 }, { outer, inner2 }), do: type_eq?(inner1, inner2)
  def type_eq?(x, x), do: true
  def type_eq?(_, _), do: false

  # Get var for given model in query
  def model_var(Query[] = query, model) do
    models = tuple_to_list(query.models)
    pos = Enum.find_index(models, &(&1 == model))
    { :&, [], [pos] }
  end

  # Find var in select clause. Returns a list of tuple and list indicies to
  # find the var.
  def locate_var({ left, right }, var) do
    locate_var({ :{}, [], [left, right] }, var)
  end

  def locate_var({ :{}, _, list }, var) do
    locate_var(list, var)
  end

  def locate_var({ :assoc, _, [left, _right] }, var) do
    if left == var, do: []
  end

  def locate_var(list, var) when is_list(list) do
    list = Stream.with_index(list)
    { poss, pos } = Enum.find_value(list, fn { elem, ix } ->
      if poss = locate_var(elem, var) do
        { poss, ix }
      else
        nil
      end
    end)
    [pos|poss]
  end

  def locate_var(expr, var) do
    if expr == var, do: []
  end

  defp escape_var(var) when is_atom(var) do
    var
  end

  defp escape_var({ var, _, context }) when is_atom(var) and is_atom(context) do
    var
  end

  defp escape_var(_) do
    raise Ecto.InvalidQuery, reason: "binding should be list of variables"
  end

  defmacrop check_merge_dup(left, right, fields) do
    Enum.map(fields, fn field ->
      quote do
        if unquote(left).unquote(field) && unquote(right).unquote(field) do
          raise Ecto.InvalidQuery, reason: "only one #{unquote(field)} expression is allowed in query"
        end
      end
    end)
  end

  # Checks if a query merge can be done
  defp check_merge(Query[] = left, Query[] = right) do
    check_merge_dup(left, right, [:select, :from, :limit, :offset])
  end
end
