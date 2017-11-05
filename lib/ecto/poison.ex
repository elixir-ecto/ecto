if Code.ensure_loaded?(Poison) do
  defimpl Poison.Encoder, for: Decimal do
    def encode(decimal, _opts), do: <<?", Decimal.to_string(decimal, :normal)::binary, ?">>
  end

  defimpl Poison.Encoder, for: Ecto.Association.NotLoaded do
    def encode(%{__owner__: owner, __field__: field}, _) do
      raise """
      cannot encode association #{inspect field} from #{inspect owner} to \
      JSON because the association was not loaded.

      You can either preload the association:

          Repo.preload(#{inspect owner}, #{inspect field})

      Or choose to not encode the association when converting the struct \
      to JSON by explicitly listing the JSON fields in your schema:

          defmodule #{inspect owner} do
            # ...

            @derive {Poison.Encoder, only: [:name, :title, ...]}
            schema ... do
      """
    end
  end
end
