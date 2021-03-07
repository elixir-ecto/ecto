defmodule Ecto.Repo.Common do
  @moduledoc false

  @doc """
  Puts the prefix given via `opts` into the given query, if available.
  """
  def attach_prefix(query, opts) do
    case Keyword.fetch(opts, :prefix) do
      {:ok, prefix} -> %{query | prefix: prefix}
      :error -> query
    end
  end
end
