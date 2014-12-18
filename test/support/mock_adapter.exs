defmodule Ecto.MockAdapter do
  @behaviour Ecto.Adapter

  defmacro __using__(_opts), do: :ok
  def start_link(_repo, _opts), do: :ok
  def stop(_repo), do: :ok
  def all(_repo, _query, _opts), do: []
  def insert(_repo, record, _opts) do
    %{ record | id: 45 } |> Map.from_struct
  end
  def update(_repo, record, _opts), do: send(self, {:update, record}) && 1
  def update_all(_repo, _query, _values, _params, _opts), do: 1
  def delete(_repo, record, _opts), do: send(self, {:delete, record}) && 1
  def delete_all(_repo, _query, _opts), do: 1

  def transaction(_repo, _opts, fun) do
    try do
      # Makes transactions "trackable" in tests
      send self, {:transaction, fun}
      {:ok, fun.()}
    catch
      _type, term ->
        {:error, term}
    end
  end
end
