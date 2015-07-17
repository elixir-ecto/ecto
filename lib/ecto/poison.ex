if Code.ensure_loaded?(Poison) do
  defimpl Poison.Encoder, for: Decimal do
    def encode(decimal, _opts), do: <<?", Decimal.to_string(decimal)::binary, ?">>
  end

  defimpl Poison.Encoder, for: [Ecto.Date, Ecto.Time, Ecto.DateTime] do
    def encode(dt, _opts), do: <<?", @for.to_iso8601(dt)::binary, ?">>
  end
end
