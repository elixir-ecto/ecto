defmodule Ecto.Adapters.SQL.Stream do
  @moduledoc false

  defstruct [:repo, :statement, :params, :mapper, :flat_map, :opts]

  def __build__(repo, statement, params, mapper, flat_map, opts) do
    %__MODULE__{repo: repo, statement: statement, params: params,
      mapper: mapper, flat_map: flat_map, opts: opts}
  end
end

defimpl Enumerable, for: Ecto.Adapters.SQL.Stream do
  def count(_), do: {:error, __MODULE__}

  def member?(_, _), do: {:error, __MODULE__}

  def reduce(stream, acc, fun) do
    %Ecto.Adapters.SQL.Stream{repo: repo, statement: statement, params: params,
                              mapper: mapper, flat_map: flat_map,
                              opts: opts} = stream
    Ecto.Adapters.SQL.reduce(repo, statement, params, mapper, flat_map, opts, acc, fun)
  end
end

defimpl Collectable, for: Ecto.Adapters.SQL.Stream do
  def into(stream) do
    %Ecto.Adapters.SQL.Stream{repo: repo, statement: statement, params: params,
                              mapper: mapper, opts: opts} = stream
    {state, fun} = Ecto.Adapters.SQL.into(repo, statement, params, mapper, opts)
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
