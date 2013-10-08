defmodule Ecto.Migration do
  defmacro __using__(_) do
    quote location: :keep do
      def __migration__, do: true
    end
  end
end