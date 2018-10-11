defmodule Ecto.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      use Ecto.Repo, unquote(opts)

      @query_event __MODULE__
                   |> Module.split()
                   |> Enum.map(& &1 |> Macro.underscore() |> String.to_atom())
                   |> Kernel.++([:query])

      def init(_, opts) do
        Telemetry.attach(__MODULE__, @query_event, Ecto.Integration.Repo, :handle_event, :ok)
        {:ok, opts}
      end
    end
  end

  def handle_event(_event, latency, metadata, _config) do
    handler = Process.delete(:telemetry) || fn _, _ -> :ok end
    handler.(latency, metadata)
  end
end
