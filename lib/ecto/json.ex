if Code.ensure_loaded?(Jason.Encoder) do
  defimpl Jason.Encoder, for: Ecto.Association.NotLoaded do
    def encode(%{__owner__: owner, __field__: field}, _) do
      raise """
      cannot encode association #{inspect(field)} from #{inspect(owner)} to \
      JSON because the association was not loaded.

      You can either preload the association:

          Repo.preload(#{inspect(owner)}, #{inspect(field)})

      Or choose to not encode the association when converting the struct \
      to JSON by explicitly listing the JSON fields in your schema:

          defmodule #{inspect(owner)} do
            # ...

            @derive {Jason.Encoder, only: [:name, :title, ...]}
            schema ... do

      You can also use the :except option instead of :only if you would \
      prefer to skip some fields.
      """
    end
  end

  defimpl Jason.Encoder, for: Ecto.Schema.Metadata do
    def encode(%{schema: schema}, _) do
      raise """
      cannot encode metadata from the :__meta__ field for #{inspect(schema)} \
      to JSON. This metadata is used internally by Ecto and should never be \
      exposed externally.

      You can either map the schemas to remove the :__meta__ field before \
      encoding or explicitly list the JSON fields in your schema:

          defmodule #{inspect(schema)} do
            # ...

            @derive {Jason.Encoder, only: [:name, :title, ...]}
            schema ... do

      You can also use the :except option instead of :only if you would \
      prefer to skip some fields.
      """
    end
  end
end

if Code.ensure_loaded?(JSON.Encoder) do
  defimpl JSON.Encoder, for: Ecto.Association.NotLoaded do
    def encode(%{__owner__: owner, __field__: field}, _) do
      raise """
      cannot encode association #{inspect(field)} from #{inspect(owner)} to \
      JSON because the association was not loaded.

      You can either preload the association:

          Repo.preload(#{inspect(owner)}, #{inspect(field)})

      Or choose to not encode the association when converting the struct \
      to JSON by explicitly listing the JSON fields in your schema:

          defmodule #{inspect(owner)} do
            # ...

            @derive {JSON.Encoder, only: [:name, :title, ...]}
            schema ... do

      You can also use the :except option instead of :only if you would \
      prefer to skip some fields.
      """
    end
  end

  defimpl JSON.Encoder, for: Ecto.Schema.Metadata do
    def encode(%{schema: schema}, _) do
      raise """
      cannot encode metadata from the :__meta__ field for #{inspect(schema)} \
      to JSON. This metadata is used internally by Ecto and should never be \
      exposed externally.

      You can either map the schemas to remove the :__meta__ field before \
      encoding or explicitly list the JSON fields in your schema:

          defmodule #{inspect(schema)} do
            # ...

            @derive {JSON.Encoder, only: [:name, :title, ...]}
            schema ... do

      You can also use the :except option instead of :only if you would \
      prefer to skip some fields.
      """
    end
  end
end
