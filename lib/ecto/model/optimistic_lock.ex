defmodule Ecto.Model.OptimisticLock do
  @moduledoc """
  This module is deprecated in favor of `Ecto.Changeset.optimistic_lock/3`.
  """

  @doc false
  defmacro __using__(_) do
    quote do
      import Ecto.Model.OptimisticLock
    end
  end

  @doc """
  This function is deprecated in favor of `Ecto.Changeset.optimistic_lock/3`.
  """
  defmacro optimistic_lock(field) do
    IO.write :stderr, "warning: the optimistic_lock/1 macro is deprecated\n" <>
                      "Please use Ecto.Changeset.optimistic_lock/3 instead.\n" <>
                      Exception.format_stacktrace(Macro.Env.stacktrace(__CALLER__))

    quote bind_quoted: [field: field] do
      before_update Ecto.Changeset, :optimistic_lock, [field]
      before_delete Ecto.Changeset, :optimistic_lock, [field]
    end
  end
end
