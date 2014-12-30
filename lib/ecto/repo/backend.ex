defmodule Ecto.Repo.Backend do
  # The backend invoked by user defined repos.
  @moduledoc false

  alias Ecto.Queryable
  alias Ecto.Query.Builder
  alias Ecto.Query.Planner
  alias Ecto.Query.SelectExpr
  alias Ecto.Model.Callbacks

  require Ecto.Query

  ## Pool related

  def start_link(repo, adapter) do
    adapter.start_link(repo, repo.conf)
  end

  def stop(repo, adapter) do
    adapter.stop(repo)
  end

  ## Queries related

  def all(repo, adapter, queryable, opts) do
    {query, params} =
      Queryable.to_query(queryable)
      |> Planner.query(%{})

    select = query.select

    case query do
      %{preloads: [], assocs: []} ->
        adapter.all(repo, query, params, &to_select(&1, select), opts)
      _ ->
        adapter.all(repo, query, params, &(&1), opts)
        |> Ecto.Associations.Assoc.query(query)
        |> Ecto.Associations.Preloader.query(repo, query)
        |> Enum.map(&to_select(&1, select)) # TODO: Remove this extra traversal
    end
  end

  def get(repo, adapter, queryable, id, opts) do
    one(repo, adapter, query_for_get(queryable, id), opts)
  end

  def get!(repo, adapter, queryable, id, opts) do
    one!(repo, adapter, query_for_get(queryable, id), opts)
  end

  def one(repo, adapter, queryable, opts) do
    case all(repo, adapter, queryable, opts) do
      [one] -> one
      []    -> nil
      other -> raise Ecto.MultipleResultsError, queryable: queryable, count: length(other)
    end
  end

  def one!(repo, adapter, queryable, opts) do
    case all(repo, adapter, queryable, opts) do
      [one] -> one
      []    -> raise Ecto.NoResultsError, queryable: queryable
      other -> raise Ecto.MultipleResultsError, queryable: queryable, count: length(other)
    end
  end

  def update_all(repo, adapter, queryable, values, opts) do
    {binds, expr} = Ecto.Query.Builder.From.escape(queryable)

    {updates, params} =
      Enum.map_reduce(values, %{}, fn {field, expr}, params ->
        {expr, params} = Builder.escape(expr, {0, field}, params, binds)
        {{field, expr}, params}
      end)

    params = Builder.escape_params(params)

    quote do
      Ecto.Repo.Backend.update_all(unquote(repo), unquote(adapter),
        unquote(expr), unquote(updates), unquote(params), unquote(opts))
    end
  end

  # The runtime callback for update all.
  def update_all(repo, adapter, queryable, updates, params, opts) do
    query = Queryable.to_query(queryable)
    model = model!(:update_all, query)

    if updates == [] do
      message = "no fields given to `update_all`"
      raise ArgumentError, message
    end

    # Check all fields are valid.
    _ = Planner.model(:update_all, model, updates, fn _type, value -> {:ok, value} end)

    # Properly cast parameters.
    params = Enum.into params, %{}, fn
      {k, {v, {0, field}}} ->
        type = model.__schema__(:field, field)
        {k, cast(:update_all, type, v)}
      {k, {v, type}} ->
        {k, cast(:update_all, type, v)}
    end

    {query, params} =
      Queryable.to_query(queryable)
      |> Planner.query(params, only_where: true)
    adapter.update_all(repo, query, updates, params, opts)
  end

  def delete_all(repo, adapter, queryable, opts) do
    {query, params} =
      Queryable.to_query(queryable)
      |> Planner.query(%{}, only_where: true)
    adapter.delete_all(repo, query, params, opts)
  end

  ## Transaction related

  def transaction(repo, adapter, opts, fun) when is_function(fun, 0) do
    adapter.transaction(repo, opts, fun)
  end

  def rollback(repo, adapter, value) do
    adapter.rollback(repo, value)
  end

  ## Model related

  def insert(repo, adapter, struct, opts) do
    with_transactions_if_callbacks repo, adapter, struct, opts,
                                   ~w(before_insert after_insert)a, fn ->
      struct = Callbacks.__apply__(struct, :before_insert)
      model  = struct.__struct__
      source = model.__schema__(:source)

      fields = Planner.struct(:insert, struct)
      result = adapter.insert(repo, source, fields, opts)

      struct
      |> build(fields, result)
      |> Callbacks.__apply__(:after_insert)
    end
  end

  def update(repo, adapter, struct, opts) do
    _ = primary_key_value!(struct)

    with_transactions_if_callbacks repo, adapter, struct, opts,
                                   ~w(before_update after_update)a, fn ->
      struct = Callbacks.__apply__(struct, :before_update)
      model  = struct.__struct__
      source = model.__schema__(:source)
      pk     = model.__schema__(:primary_key)

      params = Planner.struct(:update, struct)
      {filter, fields} = Keyword.split params, [pk]
      result = adapter.update(repo, source, filter, fields, opts)

      struct
      |> build(fields, result)
      |> Callbacks.__apply__(:after_update)
    end
  end

  def delete(repo, adapter, struct, opts) do
    with_transactions_if_callbacks repo, adapter, struct, opts,
                                   ~w(before_delete after_delete)a, fn ->
      struct = Callbacks.__apply__(struct, :before_delete)
      model  = struct.__struct__
      source = model.__schema__(:source)

      pk_field = model.__schema__(:primary_key)
      pk_value = primary_key_value!(struct)
      filter   = Planner.model(:delete, model, [{pk_field, pk_value}])

      :ok = adapter.delete(repo, source, filter, opts)
      Callbacks.__apply__(struct, :after_delete)
    end
  end

  ## Query Helpers

  defp to_select(row, %SelectExpr{expr: expr, fields: fields}) do
    {from, values} =
      case fields do
        [{:&, _, [0]}|_] -> {hd(row), tl(row)}
        _ -> {nil, row}
      end
    transform_row(expr, from, values) |> elem(0)
  end

  defp transform_row({:{}, _, list}, from, values) do
    {result, values} = transform_row(list, from, values)
    {List.to_tuple(result), values}
  end

  defp transform_row({left, right}, from, values) do
    {[left, right], values} = transform_row([left, right], from, values)
    {{left, right}, values}
  end

  defp transform_row(list, from, values) when is_list(list) do
    Enum.map_reduce(list, values, &transform_row(&1, from, &2))
  end

  defp transform_row({:&, _, [0]}, from, values) do
    {from, values}
  end

  defp transform_row(_, _from, values) do
    [value|values] = values
    {value, values}
  end

  defp query_for_get(queryable, id) do
    query = Queryable.to_query(queryable)
    model = model!(:get, query)
    primary_key = primary_key_field!(model)
    Ecto.Query.from(x in query, where: field(x, ^primary_key) == ^id)
  end

  defp model!(kind, query) do
    case query.from do
      {_source, model} when model != nil ->
        model
      _ ->
        message = "query in `#{kind}` must have a from expression with a model"
        raise Ecto.QueryError, message: message, query: query
    end
  end

  defp cast(kind, type, v) do
    case Ecto.Query.Types.cast(type, v) do
      {:ok, v} ->
        v
      :error ->
        raise ArgumentError, "value `#{inspect v}` in `#{kind}` cannot be cast to type #{inspect type}"
    end
  end

  ## Model helpers

  defp primary_key_field!(model) when is_atom(model) do
    model.__schema__(:primary_key) ||
      raise Ecto.NoPrimaryKeyError, model: model
  end

  defp primary_key_value!(struct) when is_map(struct) do
    Ecto.Model.primary_key(struct) ||
      raise Ecto.NoPrimaryKeyError, model: struct.__struct__
  end

  defp build(struct, fields, result) do
    fields
    |> Enum.with_index
    |> Enum.reduce(struct, fn {{field, _}, idx}, acc ->
         Map.put(acc, field, elem(result, idx))
       end)
  end

  defp with_transactions_if_callbacks(repo, adapter, model, opts, callbacks, fun) do
    struct = model.__struct__
    if Enum.any?(callbacks, &function_exported?(struct, &1, 1)) do
      {:ok, value} = transaction(repo, adapter, opts, fun)
      value
    else
      fun.()
    end
  end
end
