# TODO: Remove Poison handling once we have fully migrated to Jason

if Code.ensure_loaded?(Poison.Encoder) do
  defimpl Poison.Encoder, for: Decimal do
    def encode(decimal, _opts), do: <<?", Decimal.to_string(decimal, :normal)::binary, ?">>
  end
end

for encoder <- [Poison.Encoder, Jason.Encoder] do
  if Code.ensure_loaded?(encoder) do
    defimpl encoder, for: Ecto.Association.NotLoaded do
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

              @derive {#{unquote(inspect encoder)}, only: [:name, :title, ...]}
              schema ... do
        """
      end
    end

    defimpl encoder, for: Ecto.Schema.Metadata do
      def encode(%{schema: schema}, _) do
        raise """
        cannot encode metadata from the :__meta__ field for #{inspect schema} \
        to JSON. This metadata is used internally by ecto and should never be \
        exposed externally.

        You can either map the schemas to remove the :__meta__ field before \
        encoding to JSON, or explicit list the JSON fields in your schema:

            defmodule #{inspect schema} do
              # ...

              @derive {#{unquote(inspect encoder)}, only: [:name, :title, ...]}
              schema ... do
        """
      end
    end
  end
end
