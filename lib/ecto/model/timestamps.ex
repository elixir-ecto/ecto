defmodule Ecto.Model.Timestamps do
  @moduledoc """
  Automatically manage timestamps.

  If the user calls `Ecto.Schema.timestamps/0` in their schema, the
  model will automatically set callbacks based on the schema information
  to update the configured `:inserted_at` and `:updated_at` fields
  according to the given type.
  """

  defmacro __using__(_) do
    quote do
      @before_compile Ecto.Model.Timestamps
    end
  end

  import Ecto.Changeset

  @doc """
  Puts a timestamp in the changeset with the given field and type.
  """
  def put_timestamp(changeset, field, type) do
    if get_change changeset, field do
      changeset
    else
      {date, {h, m, s}} = :erlang.universaltime
      put_change changeset, field, Ecto.Type.load!(type, {date, {h, m, s, 0}})
    end
  end

  defmacro __before_compile__(env) do
    timestamps = Module.get_attribute(env.module, :timestamps)

    if timestamps do
      type = timestamps[:type]

      inserted_at = if field = Keyword.fetch!(timestamps, :inserted_at) do
        quote do
          before_insert Ecto.Model.Timestamps, :put_timestamp, [unquote(field), unquote(type)]
        end
      end

      updated_at = if field = Keyword.fetch!(timestamps, :updated_at) do
        quote do
          before_insert Ecto.Model.Timestamps, :put_timestamp, [unquote(field), unquote(type)]
          before_update Ecto.Model.Timestamps, :put_timestamp, [unquote(field), unquote(type)]
        end
      end

      {inserted_at, updated_at}
    end
  end
end