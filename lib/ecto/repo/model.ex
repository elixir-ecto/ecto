defmodule Ecto.Repo.Model do
  # The module invoked by user defined repos
  # for model related functionality.
  @moduledoc false

  alias Ecto.Model.Callbacks

  @doc """
  Implementation for `Ecto.Repo.insert/2`.
  """
  def insert(repo, adapter, struct, opts) do
    with_transactions_if_callbacks repo, adapter, struct, opts,
                                   ~w(before_insert after_insert)a, fn ->
      struct = Callbacks.__apply__(struct, :before_insert)
      model  = struct.__struct__
      source = model.__schema__(:source)

      fields = validate_struct(:insert, struct)
      {:ok, result} = adapter.insert(repo, source, fields, opts)

      struct
      |> build(fields, result)
      |> Callbacks.__apply__(:after_insert)
    end
  end

  @doc """
  Implementation for `Ecto.Repo.update/2`.
  """
  def update(repo, adapter, struct, opts) do
    with_transactions_if_callbacks repo, adapter, struct, opts,
                                   ~w(before_update after_update)a, fn ->
      struct = Callbacks.__apply__(struct, :before_update)
      model  = struct.__struct__
      source = model.__schema__(:source)

      pk_field = model.__schema__(:primary_key)
      pk_value = primary_key_value!(struct)

      fields = validate_struct(:update, struct) |> Keyword.delete(pk_field)
      {:ok, result} = adapter.update(repo, source, [{pk_field, pk_value}], fields, opts)

      struct
      |> build(fields, result)
      |> Callbacks.__apply__(:after_update)
    end
  end

  @doc """
  Implementation for `Ecto.Repo.delete/2`.
  """
  def delete(repo, adapter, struct, opts) do
    with_transactions_if_callbacks repo, adapter, struct, opts,
                                   ~w(before_delete after_delete)a, fn ->
      struct = Callbacks.__apply__(struct, :before_delete)
      model  = struct.__struct__
      source = model.__schema__(:source)

      pk_field = model.__schema__(:primary_key)
      pk_value = primary_key_value!(struct)
      filter   = validate_fields(:delete, model, [{pk_field, pk_value}])

      :ok = adapter.delete(repo, source, filter, opts)
      Callbacks.__apply__(struct, :after_delete)
    end
  end

  ## Helpers used by other modules

  @doc """
  Validates and cast the given the struct fields.
  """
  def validate_struct(kind, %{__struct__: model} = struct) do
    validate_fields(kind, model, Map.take(struct, model.__schema__(:fields)))
  end

  @doc """
  Validates and cast the given fields belonging to the given model.
  """
  def validate_fields(kind, model, kw, dumper \\ &Ecto.Query.Types.dump/2) do
    for {field, value} <- kw do
      type = model.__schema__(:field, field)

      unless type do
        raise Ecto.InvalidModelError,
          message: "field `#{inspect model}.#{field}` in `#{kind}` does not exist in the model source"
      end

      case dumper.(type, value) do
        {:ok, value} ->
          {field, value}
        :error ->
          raise Ecto.InvalidModelError,
            message: "value `#{inspect value}` for `#{inspect model}.#{field}` " <>
                     "in `#{kind}` does not match type #{inspect type}"
      end
    end
  end

  ## Internal helpers

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
      {:ok, value} = adapter.transaction(repo, opts, fun)
      value
    else
      fun.()
    end
  end
end
