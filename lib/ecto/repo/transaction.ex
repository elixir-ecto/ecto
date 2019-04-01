defmodule Ecto.Repo.Transaction do
  @moduledoc false

  @dialyzer {:no_opaque, transaction: 3}

  def transaction(name, fun, opts) when is_function(fun, 0) do
    repo_name_or_pid = Keyword.get(opts, :repo_name_or_pid, name)
    {adapter, meta} = Ecto.Repo.Registry.lookup(repo_name_or_pid)
    adapter.transaction(meta, opts, fun)
  end

  def transaction(name, %Ecto.Multi{} = multi, opts) do
    repo_name_or_pid = Keyword.get(opts, :repo_name_or_pid, name)
    {adapter, meta} = Ecto.Repo.Registry.lookup(repo_name_or_pid)
    wrap = &adapter.transaction(meta, opts, &1)
    return = &adapter.rollback(meta, &1)

    case Ecto.Multi.__apply__(multi, name, wrap, return) do
      {:ok, values} -> {:ok, values}
      {:error, {key, error_value, values}} -> {:error, key, error_value, values}
      {:error, operation} -> raise "operation #{inspect operation} is manually rolling back, which is not supported by Ecto.Multi"
    end
  end

  def in_transaction?(name, opts) do
    repo_name_or_pid = Keyword.get(opts, :repo_name_or_pid, name)
    {adapter, meta} = Ecto.Repo.Registry.lookup(repo_name_or_pid)
    adapter.in_transaction?(meta)
  end

  def rollback(name, value, opts) do
    repo_name_or_pid = Keyword.get(opts, :repo_name_or_pid, name)
    {adapter, meta} = Ecto.Repo.Registry.lookup(repo_name_or_pid)
    adapter.rollback(meta, value)
  end
end
