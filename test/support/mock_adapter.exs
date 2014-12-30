defmodule Ecto.MockAdapter do
  @behaviour Ecto.Adapter

  defmacro __using__(_opts), do: :ok
  def start_link(_repo, _opts), do: :ok
  def stop(_repo), do: :ok

  def all(_repo, _query, _params, _opts), do: [[1]]
  def update_all(_repo, _query, _values, _params, _opts), do: 1
  def delete_all(_repo, _query, _params, _opts), do: 1

  def insert(_repo, _source, fields, _opts),
    do: fields |> Keyword.values |> List.to_tuple
  def update(_repo, _source, _filter, fields, _opts),
    do: fields |> Keyword.values |> List.to_tuple
  def delete(_repo, _source, _filter, _opts),
    do: :ok

  def transaction(_repo, _opts, fun) do
    # Makes transactions "trackable" in tests
    send self, {:transaction, fun}
    {:ok, fun.()}
  end
end
