defmodule Ecto.Repo.Transaction do
  # The module invoked by user defined repos
  # for transaction related functionality.
  @moduledoc false

  @doc """
  Implementation for `Ecto.Repo.transaction/2`
  """
  def transaction(adapter, repo, opts, fun_or_multi) when is_list(opts) do
    IO.write :stderr, "warning: Ecto.Repo.transaction/2 with opts as first " <>
      "argument is deprecated, please switch arguments\n" <>
      Exception.format_stacktrace()
    transaction(adapter, repo, fun_or_multi, opts)
  end

  def transaction(adapter, repo, fun, opts) when is_function(fun, 0) do
    adapter.transaction(repo, opts, fun)
  end

  def transaction(adapter, repo, %Ecto.Multi{} = multi, opts) do
    wrap   = &adapter.transaction(repo, opts, &1)
    return = &adapter.rollback(repo, &1)

    case Ecto.Multi.apply(multi, repo, wrap, return) do
      {:ok, values} ->
        {:ok, values}
      {:error, {key, error_value, values}} ->
        {:error, key, error_value, values}
    end
  end
end
