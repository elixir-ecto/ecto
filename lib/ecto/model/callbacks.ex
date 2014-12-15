defmodule Ecto.Model.Callbacks do
  @moduledoc """
  Define module-level callbacks in models.

  A callback is invoked by your `Ecto.Repo` before (or after)
  particular events. Callbacks always run inside a transaction.

  ## Example

      defmodule User do
        use Ecto.Model.Callbacks

        before_create User, :set_default_fields
        after_create Stats, :increase_user_count

        def set_default_fields(user)
          # ...
        end
      end

  When creating the user, both callbacks will be invoked with the user as
  argument. Multiple callbacks can be defined, they will be invoked in
  order of declaration.

  ## Important

  As callbacks can be used to alter the model, please make sure to always
  return the model struct, even when unaltered.

  Callbacks will not be invoked on bulk actions such as `Repo.delete_all`
  or `Repo.update_all`.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Ecto.Model.Callbacks
      @before_compile Ecto.Model.Callbacks
      @ecto_callbacks %{}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    callbacks = Module.get_attribute env.module, :ecto_callbacks

    for {event, callbacks} <- callbacks do
      callbacks = Enum.reverse(callbacks)

      quote bind_quoted: [event: event, callbacks: callbacks] do
        def unquote(event)(model) do

          Enum.reduce unquote(callbacks), model, fn({mod, fun}, acc) ->
            apply(mod, fun, [acc])
          end
        end
      end
    end
  end

  # Callback macros

  @doc """
  Adds a callback to the model that is invoked before the model is inserted
  into the database.

  Takes the module and the function that are to be invoked as parameters.

  ## Example

      before_insert User, :generate_permalink

  """
  defmacro before_insert(module, function),
    do: register_callback(:before_insert, module, function)

  @doc """
  Adds a callback to the model that is invoked after the model is inserted
  into the database.

  Takes the module and the function that are to be invoked as parameters.

  ## Example

      after_insert Stats, :increase_user_count

  """
  defmacro after_insert(module, function),
    do: register_callback(:after_insert, module, function)

  @doc """
  Adds a callback to the model that is invoked before the model is updated.

  Takes the module and the function that are to be invoked as parameters.

  ## Example

    before_update User, :set_update_at_timestamp

  """
  defmacro before_update(module, function),
   do: register_callback(:before_update, module, function)

  @doc """
  Adds a callback to the model that is invoked after the model is updated.

  Takes the module and the function that are to be invoked as parameters.

  ## Example

      after_update User, :notify_account_change

  """
  defmacro after_update(module, function),
    do: register_callback(:after_update, module, function)

  @doc """
  Adds a callback to the model that is invoked before the model is deleted
  from the database.

  Takes the module and the function that are to be invoked as parameters.

  ## Example

      before_delete User, :copy_to_archive

  """
  defmacro before_delete(module, function),
    do: register_callback(:before_delete, module, function)

  @doc """
  Adds a callback to the model that is invoked before the model is deleted
  from the database.

  Takes the module and the function that are to be invoked as parameters.

  ## Example

      after_delete UserMailer, :send_questioneer

  """
  defmacro after_delete(module, function),
    do: register_callback(:after_delete, module, function)

  defp register_callback(event, module, function) do
    quote bind_quoted: [event: event, callback: {module, function}] do
      @ecto_callbacks Map.update(@ecto_callbacks, event, [callback], &[callback|&1])
    end
  end

  @doc """
  Applies stored callbacks to a model.

  Checks wether the callback is defined on the model, returns the model
  unchanged if it isn't.

  ## Examples

      iex> Ecto.Model.Callbacks.__apply__ %User{}, :before_create
      %User{some_var: "has changed"}

  """
  def __apply__(%{__struct__: module} = model, callback) do
    if function_exported?(module, callback, 1) do
      apply module, callback, [model]
    else
      model
    end
  end
end
