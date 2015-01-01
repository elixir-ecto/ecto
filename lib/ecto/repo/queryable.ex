defmodule Ecto.Repo.Queryable do
  # The module invoked by user defined repos
  # for query related functionality.
  @moduledoc false

  alias Ecto.Queryable
  alias Ecto.Query.Builder
  alias Ecto.Query.Planner

  require Ecto.Query

  @doc """
  Implementation for `Ecto.Repo.all/2`
  """
  def all(repo, adapter, queryable, opts) do
    {query, params} =
      Queryable.to_query(queryable)
      |> Planner.query(%{})

    adapter.all(repo, query, params, opts)
    |> Ecto.Repo.Assoc.query(query)
    |> Ecto.Repo.Preloader.query(repo, query, to_select(query.select))
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
  Implementation for `Ecto.Repo.update_all/3`
  """
  def update_all(repo, adapter, queryable, values, opts) do
    {binds, expr} = Ecto.Query.Builder.From.escape(queryable)

    {updates, params} =
      Enum.map_reduce(values, %{}, fn {field, expr}, params ->
        {expr, params} = Builder.escape(expr, {0, field}, params, binds)
        {{field, expr}, params}
      end)

    params = Builder.escape_params(params)

    quote do
      Ecto.Repo.Queryable.update_all(unquote(repo), unquote(adapter),
        unquote(expr), unquote(updates), unquote(params), unquote(opts))
    end
  end

  @doc """
  Runtime callback for `Ecto.Repo.update_all/3`
  """
  def update_all(repo, adapter, queryable, updates, params, opts) do
    query = Queryable.to_query(queryable)

    if updates == [] do
      message = "no fields given to `update_all`"
      raise ArgumentError, message
    end

    # If we have a model in the query, let's use it for casting.
    case query.from do
      {source, model} when model != nil ->
        # Check all fields are valid but don't use dump as we'll cast below.
        _ = Ecto.Repo.Model.validate_fields(:update_all, model, updates,
                                            fn _type, value -> {:ok, value} end)

        # Properly cast parameters.
        params = Enum.into params, %{}, fn
          {k, {v, {0, field}}} ->
            type = model.__schema__(:field, field)
            {k, cast(:update_all, type, v)}
          {k, {v, type}} ->
            {k, cast(:update_all, type, v)}
        end
      _ ->
        :ok
    end

    {query, params} =
      Queryable.to_query(queryable)
      |> Planner.query(params, only_where: true)
    adapter.update_all(repo, query, updates, params, opts)
  end

  @doc """
  Implementation for `Ecto.Repo.delete_all/2`
  """
  def delete_all(repo, adapter, queryable, opts) do
    {query, params} =
      Queryable.to_query(queryable)
      |> Planner.query(%{}, only_where: true)
    adapter.delete_all(repo, query, params, opts)
  end

  ## Helpers

  defp to_select(select) do
    expr  = select.expr
    from? = match?([{:&, _, [0]}|_], select.fields)
    &to_select(&1, expr, from?)
  end

  defp to_select(row, expr, true),
    do: transform_row(expr, hd(row), tl(row)) |> elem(0)
  defp to_select(row, expr, false),
    do: transform_row(expr, nil, row) |> elem(0)

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
    model = Ecto.Query.Planner.assert_model!(query)
    primary_key = primary_key_field!(model)
    Ecto.Query.from(x in query, where: field(x, ^primary_key) == ^id)
  end

  defp cast(kind, type, v) do
    case Ecto.Query.Types.cast(type, v) do
      {:ok, v} ->
        v
      :error ->
        raise ArgumentError,
          "value `#{inspect v}` in `#{kind}` cannot be cast to type #{inspect type}"
    end
  end

  defp primary_key_field!(model) when is_atom(model) do
    model.__schema__(:primary_key) ||
      raise Ecto.NoPrimaryKeyError, model: model
  end
end
