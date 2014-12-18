defmodule Ecto.Query.Validator do
  @moduledoc false

  # This module does validation on the query checking that it's in
  # a correct format, raising if it's not.

  # TODO: Check it raises on missing bindings

  alias Ecto.Query
  alias Ecto.Query.Util
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Associations.Assoc

  require Ecto.Query.Util

  def validate(query, apis, opts \\ []) do
    if query.from == nil do
      raise Ecto.QueryError, reason: "a query must have a from expression"
    end

    state = %{new_state() | sources: query.sources, apis: apis, from: query.from, query: query}

    validate_preloads(query, state)
    validate_limit(query, state)
    validate_offset(query, state)

    unless opts[:skip_select] do
      validate_select(query, state)
      preload_selected(query)
    end
  end

  def validate_update(query, apis, values, _params) do
    validate_only_where(query)

    if values == [] do
      raise Ecto.QueryError, reason: "no values to update given"
    end

    if model = Util.model(query.from) do
      Enum.each(values, fn {field, _expr} ->
        expected_type = model.__schema__(:field_type, field)

        unless expected_type do
          raise Ecto.QueryError, reason: "field `#{field}` is not on the " <>
            "model `#{inspect model}`"
        end
      end)
    end

    validate(query, apis, skip_select: true)
  end

  def validate_delete(query, apis) do
    validate_only_where(query)
    validate(query, apis, skip_select: true)
  end

  def validate_get(query, apis) do
    validate_only_where(query)
    validate(query, apis, skip_select: true)
  end

  defp validate_only_where(query) do
    # Update validation check if assertion fails
    unquote(unless map_size(%Query{}) == 14, do: raise "Ecto.Query out of date")

    # TODO: File and line metadata
    unless match?(%Query{joins: [], select: nil, order_bys: [], limit: nil,
        offset: nil, group_bys: [], havings: [], preloads: [], distincts: [], lock: nil}, query) do
      raise Ecto.QueryError, reason: "query can only have `where` expressions"
    end
  end
  
  defp validate_limit(%Query{limit: nil}, _), do: :ok

  defp validate_limit(query, _state) do
    if contains_variable?(query.limit.expr) do
      raise Ecto.QueryError, reason: "variables not allowed in limit expression"
    end
  end

  defp validate_offset(%Query{offset: nil}, _), do: :ok

  defp validate_offset(query, _state) do
    if contains_variable?(query.offset.expr) do
      raise Ecto.QueryError, reason: "variables not allowed in offset expression"
    end
  end

  defp validate_preloads(query, %{from: from}) do
    model = Util.model(from)

    if query.preloads != [] and is_nil(model) do
      raise Ecto.QueryError, reason: "can only preload on fields from a model"
    end

    Enum.each(query.preloads, fn expr ->
      rescue_metadata(query, :preload, expr, fn ->
        check_preload_fields(expr.expr, model)
      end)
    end)
  end

  defp check_preload_fields(fields, model) do
    Enum.map(fields, fn {field, sub_fields} ->
      refl = model.__schema__(:association, field)
      unless refl do
        raise Ecto.QueryError, reason: "`#{inspect model}.#{field}` is not an association field"
      end
      check_preload_fields(sub_fields, refl.associated)
    end)
  end

  defp validate_select(query, state) do
    rescue_metadata(query, :select, query.select, fn ->
      state = %{state | params: query.select.params}
      select_clause(query.select.expr, state)
    end)
  end

  defp preload_selected(query) do
    unless query.preloads == [] do
      rescue_metadata(query, :select, query.select, fn ->
        pos = Util.locate_var(query.select.expr, {:&, [], [0]})
        if is_nil(pos) do
          raise Ecto.QueryError, reason: "source in from expression " <>
            "needs to be selected when using preload query"
        end
      end)
    end
  end

  # Handle top level select cases

  defp select_clause({:assoc, _, [var, fields]}, state) do
    assoc_select(var, fields, state)
  end

  defp select_clause({left, right}, state) do
    select_clause(left, state)
    select_clause(right, state)
  end

  defp select_clause({:{}, _, list}, state) do
    Enum.each(list, &select_clause(&1, state))
  end

  defp select_clause(list, state) when is_list(list) do
    Enum.each(list, &select_clause(&1, state))
  end

  defp select_clause(other, _state) do
    other
  end

  defp assoc_select(parent_var, fields, %{query: query, sources: sources} = state) do
    Enum.each(fields, fn {field, nested} ->
      {child_var, nested_fields} = Assoc.decompose_assoc(nested)
      parent_model = Util.find_source(sources, parent_var) |> Util.model

      refl = parent_model.__schema__(:association, field)
      unless refl do
        raise Ecto.QueryError, reason: "field `#{inspect parent_model}.#{field}` is not an association"
      end

      child_model = Util.find_source(sources, child_var) |> Util.model
      unless refl.associated == child_model do
        raise Ecto.QueryError, reason: "association on `#{inspect parent_model}.#{field}` " <>
          "doesn't match given model: `#{child_model}`"
      end

      unless child_model.__schema__(:primary_key) do
        raise Ecto.QueryError, reason: "`assoc/2` selector requires a primary key on " <>
          "model: `#{child_model}`"
      end

      case Util.source_expr(query, child_var) do
        %JoinExpr{qual: qual, assoc: assoc} when not is_nil(assoc) and qual in [:inner, :left] ->
          :ok
        %JoinExpr{} ->
          raise Ecto.QueryError, reason: "can only associate on an inner or left association join"
        _ ->
          :ok
      end

      assoc_select(child_var, nested_fields, state)
    end)
  end


  defp contains_variable?({:&, _, _}),
    do: true
  defp contains_variable?({left, _, right}),
    do: contains_variable?(left) or contains_variable?(right)
  defp contains_variable?({left, right}),
    do: contains_variable?(left) or contains_variable?(right)
  defp contains_variable?(list) when is_list(list),
    do: Enum.any?(list, &contains_variable?/1)
  defp contains_variable?(_),
    do: false

  # Adds type, file and line metadata to the exception
  defp rescue_metadata(query, type, %QueryExpr{expr: expr, file: file, line: line}, fun) do
    try do
      fun.()
    rescue
      e in [Ecto.QueryError] ->
        stacktrace = System.stacktrace
        reraise %{e | type: type, query: query, expr: expr, file: file, line: line}, stacktrace
      e in [Ecto.Query.TypeCheckError] ->
        stacktrace = System.stacktrace
        reraise %{e | query: query, expr: expr, file: file, line: line}, stacktrace
    end
  end

  defp new_state do
    %{sources: [], vars: [], apis: nil, from: nil,
      query: nil, params: nil}
  end
end
