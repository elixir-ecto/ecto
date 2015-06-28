defmodule Ecto.Repo.Queryable do
  # The module invoked by user defined repos
  # for query related functionality.
  @moduledoc false

  alias Ecto.Queryable
  alias Ecto.Query.Planner

  require Ecto.Query

  @doc """
  Implementation for `Ecto.Repo.all/2`
  """
  def all(repo, adapter, queryable, opts) when is_list(opts) do
    id_types = adapter.id_types(repo)

    {query, params} =
      Queryable.to_query(queryable)
      |> Planner.query(:all, [], id_types)

    adapter.all(repo, query, params, opts)
    |> Ecto.Repo.Assoc.query(query)
    |> Ecto.Repo.Preloader.query(repo, query, to_select(query.select, id_types))
  end

  @doc """
  Implementation for `Ecto.Repo.get/3`
  """
  def get(repo, adapter, queryable, id, opts) do
    one(repo, adapter, query_for_get(queryable, id), opts)
  end

  @doc """
  Implementation for `Ecto.Repo.get!/3`
  """
  def get!(repo, adapter, queryable, id, opts) do
    one!(repo, adapter, query_for_get(queryable, id), opts)
  end

  def get_by(repo, adapter, queryable, clauses, opts) do
    one(repo, adapter, query_for_get_by(queryable, clauses), opts)
  end

  def get_by!(repo, adapter, queryable, clauses, opts) do
    one!(repo, adapter, query_for_get_by(queryable, clauses), opts)
  end

  @doc """
  Implementation for `Ecto.Repo.one/2`
  """
  def one(repo, adapter, queryable, opts) do
    case all(repo, adapter, queryable, opts) do
      [one] -> one
      []    -> nil
      other -> raise Ecto.MultipleResultsError, queryable: queryable, count: length(other)
    end
  end

  @doc """
  Implementation for `Ecto.Repo.one!/2`
  """
  def one!(repo, adapter, queryable, opts) do
    case all(repo, adapter, queryable, opts) do
      [one] -> one
      []    -> raise Ecto.NoResultsError, queryable: queryable
      other -> raise Ecto.MultipleResultsError, queryable: queryable, count: length(other)
    end
  end

  @doc """
  Runtime callback for `Ecto.Repo.update_all/3`
  """
  def update_all(repo, adapter, queryable, [], opts) when is_list(opts) do
    update_all(repo, adapter, queryable, opts)
  end

  def update_all(repo, adapter, queryable, updates, opts) when is_list(opts) do
    if Keyword.has_key?(updates, :set) or Keyword.has_key?(updates, :inc) do
      query = Ecto.Query.from q in queryable, update: ^updates
      update_all(repo, adapter, query, opts)
    else
      raise ArgumentError, """
      You are using the deprecated update syntax. Instead of:

          Repo.update_all queryable, foo: "bar"

      One should write:

          Repo.update_all queryable, set: [foo: "bar"]

      Where `:set` is the update operator. `:inc` is also
      supported to increment a given column by the given value:

          Repo.update_all queryable, inc: [foo: 1]

      For complex expressions, updates are now also supported in
      queries:

          query = from queryable, update: [set: [foo: p.bar]]
          Repo.update_all query, []
      """
    end
  end

  defp update_all(repo, adapter, queryable, opts) do
    {query, params} =
      Queryable.to_query(queryable)
      |> Planner.query(:update_all, [], adapter.id_types(repo))
    adapter.update_all(repo, query, params, opts)
  end

  @doc """
  Implementation for `Ecto.Repo.delete_all/2`
  """
  def delete_all(repo, adapter, queryable, opts) when is_list(opts) do
    {query, params} =
      Queryable.to_query(queryable)
      |> Planner.query(:delete_all, [], adapter.id_types(repo))
    adapter.delete_all(repo, query, params, opts)
  end

  ## Helpers

  defp to_select(select, id_types) do
    expr  = select.expr
    # The planner always put the from as the first
    # entry in the query, avoiding fetching it multiple
    # times even if it appears multiple times in the query.
    # So we always need to handle it specially.
    from? = match?([{:&, _, [0]}|_], select.fields)
    &to_select(&1, expr, from?, id_types)
  end

  defp to_select(row, expr, true, id_types),
    do: transform_row(expr, hd(row), tl(row), id_types) |> elem(0)
  defp to_select(row, expr, false, id_types),
    do: transform_row(expr, nil, row, id_types) |> elem(0)

  defp transform_row({:{}, _, list}, from, values, id_types) do
    {result, values} = transform_row(list, from, values, id_types)
    {List.to_tuple(result), values}
  end

  defp transform_row({left, right}, from, values, id_types) do
    {[left, right], values} = transform_row([left, right], from, values, id_types)
    {{left, right}, values}
  end

  defp transform_row({:%{}, _, pairs}, from, values, id_types) do
    Enum.reduce pairs, {%{}, values}, fn({key, value}, {map, values_acc}) ->
      {value, new_values} = transform_row(value, from, values_acc, id_types)
      {Map.put(map, key, value), new_values}
    end
  end

  defp transform_row(list, from, values, id_types) when is_list(list) do
    Enum.map_reduce(list, values, &transform_row(&1, from, &2, id_types))
  end

  defp transform_row(%Ecto.Query.Tagged{tag: tag}, _from, values, id_types) when not is_nil(tag) do
    [value|values] = values
    type = Ecto.Type.normalize(tag, id_types)
    {Ecto.Type.load!(type, value), values}
  end

  defp transform_row({:&, _, [0]}, from, values, _id_types) do
    {from, values}
  end

  defp transform_row({{:., _, [{:&, _, [_]}, _]}, meta, []}, _from, values, id_types) do
    [value|values] = values

    if type = Keyword.get(meta, :ecto_type) do
      type = Ecto.Type.normalize(type, id_types)
      {Ecto.Type.load!(type, value), values}
    else
      {value, values}
    end
  end

  defp transform_row(_, _from, values, _id_types) do
    [value|values] = values
    {value, values}
  end

  defp query_for_get(queryable, id) do
    query = Queryable.to_query(queryable)
    model = assert_model!(query)
    primary_key = primary_key_field!(model)
    Ecto.Query.from(x in query, where: field(x, ^primary_key) == ^id)
  end

  defp query_for_get_by(queryable, clauses) do
    Enum.reduce(clauses, queryable, fn({field, value}, query) ->
      query |> Ecto.Query.where([x], field(x, ^field) == ^value)
    end)
  end

  defp assert_model!(query) do
    case query.from do
      {_source, model} when model != nil ->
        model
      _ ->
        raise Ecto.QueryError,
          query: query,
          message: "expected a from expression with a model"
    end
  end

  defp primary_key_field!(model) when is_atom(model) do
    case model.__schema__(:primary_key) do
      [field] -> field
      _ -> raise Ecto.NoPrimaryKeyError, model: model
    end
  end
end
