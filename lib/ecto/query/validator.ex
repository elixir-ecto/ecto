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
