defmodule Ecto.Model.Callbacks do
  @moduledoc ~S"""
  Define module-level callbacks in models.
  """
  defmacro callbacks([do: block]) do
    quote do
      @ecto_callbacks []
      import Ecto.Model.Callbacks, only: [on: 2]
      unquote block
      import Ecto.Model.Callbacks, only: []

      def __callbacks__(event) do
        Keyword.get_values(@ecto_callbacks, event)
      end
    end
  end

  defmacro on(event, function) do
    quote do
      Ecto.Model.Callbacks.register_callback __MODULE__, unquote(event),
                                             unquote(function)
    end
  end

  def register_callback(mod, name, function) do
    callbacks =
      Module.get_attribute(mod, :ecto_callbacks) ++
      Keyword.new([{name, function}])

    Module.put_attribute mod, :ecto_callbacks, callbacks
  end

  def apply_callbacks(model, event) do
    model.__struct__.__callbacks__(event)
    |> Enum.reduce(model, fn(callback, model) -> callback.(model) end)
  end
end
