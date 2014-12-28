defmodule Ecto.Repo.Backend do
  # The backend invoked by user defined repos.
  @moduledoc false

  alias Ecto.Queryable
  alias Ecto.Query.Builder
  alias Ecto.Query.Planner
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
    results = adapter.all(repo, query, params, opts)
    preload_for_all(repo, query, results)
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

  defp preload_for_all(_repo, %{preloads: []}, results), do: results
  defp preload_for_all(repo, query, results) do
    var      = {:&, [], [0]}
    expr     = query.select.expr
    preloads = List.flatten(query.preloads)

    cond do
      is_var?(expr, var) ->
        Ecto.Associations.Preloader.run(results, repo, preloads)
      pos = select_var(expr, var) ->
        Ecto.Associations.Preloader.run(results, repo, preloads, pos)
      true ->
        message = "source in from expression needs to be directly selected " <>
                  "when using preload or inside a single tuple or list"
        raise Ecto.QueryError, message: message, query: query
    end
  end

  defp is_var?({:assoc, _, [expr, _right]}, var),
    do: expr == var
  defp is_var?(expr, var),
    do: expr == var

  defp select_var({left, right}, var),
    do: select_var({:{}, [], [left, right]}, var)
  defp select_var({:{}, _, list}, var),
    do: select_var(list, var)
  defp select_var(list, var) when is_list(list),
    do: Enum.find_index(list, &is_var?(&1, var))
  defp select_var(_, _),
    do: nil

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
