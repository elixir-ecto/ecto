defmodule Ecto.Adapters.SQL.Stream do
  @moduledoc false

  defstruct [:meta, :statement, :params, :opts]

  def build(meta, statement, params, opts) do
    %__MODULE__{meta: meta, statement: statement, params: params, opts: opts}
  end
end

alias Ecto.Adapters.SQL.Stream

defimpl Enumerable, for: Stream do
  def count(_), do: {:error, __MODULE__}

  def member?(_, _), do: {:error, __MODULE__}

  def slice(_), do: {:error, __MODULE__}

  def reduce(stream, acc, fun) do
    %Stream{meta: meta, statement: statement, params: params, opts: opts} = stream
    Ecto.Adapters.SQL.reduce(meta, statement, params, opts, acc, fun)
  end
end

defimpl Collectable, for: Stream do
  def into(stream) do
    %Stream{meta: meta, statement: statement, params: params, opts: opts} = stream
    {state, fun} = Ecto.Adapters.SQL.into(meta, statement, params, opts)
    {state, make_into(fun, stream)}
  end

  defp make_into(fun, stream) do
    fn
      state, :done ->
        fun.(state, :done)
        stream

      state, acc ->
        fun.(state, acc)
    end
  end
end
