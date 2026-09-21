defmodule Ecto.Repo.Transaction do
  @moduledoc false
  @dialyzer :no_opaque

  def transact(repo, name, fun, adapter_opts) when is_function(fun, 0) do
    transact(repo, name, fn _repo -> fun.() end, adapter_opts)
  end

  def transact(repo, _name, fun, {adapter_meta, opts}) when is_function(fun, 1) do
    adapter_meta.adapter.transaction(adapter_meta, opts, fn ->
      case fun.(repo) do
        {:ok, result} ->
          result

        {:error, reason} ->
          adapter_meta.adapter.rollback(adapter_meta, reason)

        other ->
          raise ArgumentError,
                "expected to return {:ok, _} or {:error, _}, got: #{inspect(other)}"
      end
    end)
  end

  def transact(repo, _name, %Ecto.Multi{} = multi, {adapter_meta, opts}) do
    %{adapter: adapter} = adapter_meta
    wrap = &adapter.transaction(adapter_meta, opts, &1)
    return = &adapter.rollback(adapter_meta, &1)

    case Ecto.Multi.__apply__(multi, repo, wrap, return) do
      {:ok, values} ->
        {:ok, values}

      {:error, {key, error_value, values}} ->
        {:error, key, error_value, values}

      {:error, operation} ->
        raise """
        operation #{inspect(operation)} is rolling back unexpectedly.

        This can happen if `repo.rollback/1` is manually called, which is not \
        supported by `Ecto.Multi`. It can also occur if a nested transaction \
        has rolled back and its error is not bubbled up to the outer multi. \
        Nested transactions are discouraged when using `Ecto.Multi`. Consider \
        flattening out the transaction instead.
        """
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
