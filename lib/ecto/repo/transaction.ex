defmodule Ecto.Repo.Transaction do
  @moduledoc false
  @dialyzer :no_opaque

  def transaction(_repo, name, fun, opts) when is_function(fun, 0) do
    {adapter, meta} = Ecto.Repo.Registry.lookup(name)
    adapter.transaction(meta, opts, fun)
  end
  
  def transaction(repo, name, fun, opts) when is_function(fun, 1) do
    {adapter, meta} = Ecto.Repo.Registry.lookup(name)
    adapter.transaction(meta, opts, fn -> fun.(repo) end)
  end

  def transaction(repo, name, %Ecto.Multi{} = multi, opts) do
    {adapter, meta} = Ecto.Repo.Registry.lookup(name)
    wrap = &adapter.transaction(meta, opts, &1)
    return = &adapter.rollback(meta, &1)

    case Ecto.Multi.__apply__(multi, repo, wrap, return) do
      {:ok, values} -> {:ok, values}
      {:error, {key, error_value, values}} -> {:error, key, error_value, values}
      {:error, operation} -> raise "operation #{inspect operation} is manually rolling back, which is not supported by Ecto.Multi"
    end
  end

  def in_transaction?(name) do
    {adapter, meta} = Ecto.Repo.Registry.lookup(name)
    adapter.in_transaction?(meta)
  end

  def rollback(name, value) do
    {adapter, meta} = Ecto.Repo.Registry.lookup(name)
    adapter.rollback(meta, value)
  end
end
