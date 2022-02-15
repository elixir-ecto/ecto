defmodule Ecto.Repo.Transaction do
  @moduledoc false
  @dialyzer :no_opaque

  def transaction(_repo, _name, fun, {adapter_meta, opts}) when is_function(fun, 0) do
    adapter_meta.adapter.transaction(adapter_meta, opts, fun)
  end
  
  def transaction(repo, _name, fun, {adapter_meta, opts}) when is_function(fun, 1) do
    adapter_meta.adapter.transaction(adapter_meta, opts, fn -> fun.(repo) end)
  end

  def transaction(repo, _name, %Ecto.Multi{} = multi, {adapter_meta, opts}) do
    %{adapter: adapter} = adapter_meta
    wrap = &adapter.transaction(adapter_meta, opts, &1)
    return = &adapter.rollback(adapter_meta, &1)

    case Ecto.Multi.__apply__(multi, repo, wrap, return) do
      {:ok, values} -> {:ok, values}
      {:error, {key, error_value, values}} -> {:error, key, error_value, values}
      {:error, operation} -> raise "operation #{inspect operation} is manually rolling back, which is not supported by Ecto.Multi"
    end
  end

  def in_transaction?(name) do
    %{adapter: adapter} = meta = Ecto.Repo.Registry.lookup(name)
    adapter.in_transaction?(meta)
  end

  def rollback(name, value) do
    %{adapter: adapter} = meta = Ecto.Repo.Registry.lookup(name)
    adapter.rollback(meta, value)
  end
end
