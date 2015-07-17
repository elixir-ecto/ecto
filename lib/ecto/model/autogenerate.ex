defmodule Ecto.Model.Autogenerate do
  @moduledoc """
  Handle autogenerate columns via callbacks.
  """
  defmacro __using__(_) do
    quote do
      @before_compile Ecto.Model.Autogenerate
    end
  end

  @doc """
  Autogenerates the given key-values in changeset.
  """
  def autogenerate(changeset, autogenerate) do
    update_in changeset.changes, fn changes ->
      Enum.reduce autogenerate, changes, fn {k, v}, acc ->
        if Map.get(acc, k) == nil do
          Map.put(acc, k, v.generate())
        else
          acc
        end
      end
    end
  end

  defmacro __before_compile__(env) do
    autogenerate = Module.get_attribute(env.module, :ecto_autogenerate)

    if autogenerate != [] do
      quote do
        before_insert Ecto.Model.Autogenerate, :autogenerate, [unquote(autogenerate)]
      end
    end
  end
end
