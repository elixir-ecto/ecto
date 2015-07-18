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
  def put_timestamp(changeset, field, type, use_usec) do
    if get_change changeset, field do
      changeset
    else
      {:ok, value} = Ecto.Type.load(type, timestamp_tuple(use_usec))
      force_change changeset, field, value
    end
  end

  defp timestamp_tuple(_use_usec = true) do
    erl_timestamp = :os.timestamp
    {_, _, usec} = erl_timestamp
    {date, {h, m, s}} =:calendar.now_to_datetime(erl_timestamp)
    {date, {h, m, s, usec}}
  end

  defp timestamp_tuple(_use_usec = false) do
    {date, {h, m, s}} = :erlang.universaltime
    {date, {h, m, s, 0}}
  end

  defmacro __before_compile__(env) do
    timestamps = Module.get_attribute(env.module, :ecto_timestamps)

    if timestamps do
      args = [timestamps[:type], timestamps[:usec]]

      inserted_at =
        if field = Keyword.fetch!(timestamps, :inserted_at) do
          quote do
            before_insert Ecto.Model.Timestamps, :put_timestamp, [unquote(field)|args]
          end
        end

      updated_at =
        if field = Keyword.fetch!(timestamps, :updated_at) do
          quote do
            before_insert Ecto.Model.Timestamps, :put_timestamp, [unquote(field)|args]
            before_update Ecto.Model.Timestamps, :put_timestamp, [unquote(field)|args]
          end
        end

      quote do
        args = unquote(args)
        unquote(inserted_at)
        unquote(updated_at)
      end
    end
  end
end
