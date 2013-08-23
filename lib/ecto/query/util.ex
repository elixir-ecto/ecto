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
  Look up an entity with a variable.
  """
  def find_entity(entities, { :&, _, [ix] }) when is_tuple(entities) do
    elem(entities, ix)
  end

  def find_entity(entities, { :&, _, [ix] }) when is_list(entities) do
    Enum.at(entities, ix)
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
  def value_to_type(nil), do: nil
  def value_to_type(value) when is_boolean(value), do: :boolean
  def value_to_type(value) when is_binary(value), do: :string
  def value_to_type(value) when is_integer(value), do: :integer
  def value_to_type(value) when is_float(value), do: :float

  def value_to_type(list) when is_list(list) do
    types = Enum.map(list, &value_to_type/1)

    case types do
      [] ->
        { :list, :any }
      [type|rest] ->
        unless Enum.all?(rest, &type_eq?(type, &1)) do
          raise Ecto.InvalidQuery, reason: "all elements in list has to be of same type"
        end
        { :list, type }
    end
  end

  # Returns true if the two types are considered equal by the type system
  @doc false
  def type_eq?(_, :any), do: true
  def type_eq?(:any, _), do: true
  def type_eq?({ outer, inner1 }, { outer, inner2 }), do: type_eq?(inner1, inner2)
  def type_eq?(x, x), do: true
  def type_eq?(_, _), do: false

  # Get query var from entity
  def from_entity_var(Query[] = query) do
    entity_var(query, query.from)
  end

  # Get var for given entity in query
  def entity_var(Query[] = query, entity) do
    entities = tuple_to_list(query.entities)
    pos = Enum.find_index(entities, &(&1 == entity))
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
