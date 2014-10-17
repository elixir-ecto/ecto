defmodule Ecto.Model.Callbacks do
  @moduledoc ~S"""
  Define module-level callbacks in models.
  """

  @events [:before_insert, :before_update, :before_delete]

  defmacro __using__(_opts) do
    quote do
      @ecto_callbacks []

      import Ecto.Model.Callbacks, only: unquote(@events |> Enum.map(&{&1, 1}) |> Keyword.new)
    end
  end

  for event <- @events do
    defmacro unquote(event)(function) do
      event = unquote(event)
      quote unquote: true, bind_quoted: [event: event] do
        Ecto.Model.Callbacks.register_callback(__MODULE__, event, unquote(function))
        def __callbacks__(event), do: Keyword.get_values(@ecto_callbacks, event)
        Module.make_overridable(__MODULE__, [__callbacks__: 1])
      end
    end
  end

  def register_callback(mod, name, function) do
    callbacks =
      Module.get_attribute(mod, :ecto_callbacks) ++
      Keyword.new([{name, function}])

    Module.put_attribute mod, :ecto_callbacks, callbacks
  end

  def apply_callbacks(model, event) do
    apply(model.__struct__, :__callbacks__, [event])
    |> Enum.reduce(model, &apply_callback/2)
  end

  def apply_callback(callback, model) when is_atom(callback) do
    apply(model.__struct__, callback, [model])
  end

  def apply_callback(callback, model) when is_function(callback) do
    callback.(model)
  end

  def apply_callback(callback, model) do
    raise ArgumentError, message: "callbacks must be atoms or functions, " <>
                                  "got: #{Macro.to_string(callback)}"
  end
end
