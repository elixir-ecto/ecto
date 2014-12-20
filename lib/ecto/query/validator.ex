defmodule Ecto.Query.Validator do
  @moduledoc false

  # This module does validation on the query checking that it's in
  # a correct format, raising if it's not.

  alias Ecto.Query
  alias Ecto.Query.Util
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Associations.Assoc

  require Ecto.Query.Util

  def validate(query, opts \\ []) do
    unless opts[:skip_select] do
      validate_select(query)
      preload_selected(query)
    end
  end

  def validate_update(query, values, _params) do
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

    validate(query, skip_select: true)
  end

  def validate_delete(query) do
    validate_only_where(query)
    validate(query, skip_select: true)
  end

  def validate_get(query) do
    validate_only_where(query)
    validate(query, skip_select: true)
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

  defp validate_select(query) do
    rescue_metadata(query, :select, query.select, fn ->
      select_clause(query.select.expr, query)
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

  defp select_clause({:assoc, _, [var, fields]}, query) do
    assoc_select(var, fields, query)
  end

  defp select_clause({left, right}, query) do
    select_clause(left, query)
    select_clause(right, query)
  end

  defp select_clause({:{}, _, list}, query) do
    Enum.each(list, &select_clause(&1, query))
  end

  defp select_clause(list, query) when is_list(list) do
    Enum.each(list, &select_clause(&1, query))
  end

  defp select_clause(other, _query) do
    other
  end

  defp assoc_select(parent_var, fields, query) do
    Enum.each(fields, fn {field, nested} ->
      {child_var, nested_fields} = Assoc.decompose_assoc(nested)
      parent_model = Util.find_source(query.sources, parent_var) |> Util.model

      refl = parent_model.__schema__(:association, field)
      unless refl do
        raise Ecto.QueryError, reason: "field `#{inspect parent_model}.#{field}` is not an association"
      end

      child_model = Util.find_source(query.sources, child_var) |> Util.model
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

      assoc_select(child_var, nested_fields, query)
    end)
  end

  # Adds type, file and line metadata to the exception
  defp rescue_metadata(query, type, %QueryExpr{expr: expr, file: file, line: line}, fun) do
    try do
      fun.()
    rescue
      e in [Ecto.QueryError] ->
        stacktrace = System.stacktrace
        reraise %{e | type: type, query: query, expr: expr, file: file, line: line}, stacktrace
    end
  end
end
