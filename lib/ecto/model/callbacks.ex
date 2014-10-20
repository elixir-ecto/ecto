defmodule Ecto.Model.Callbacks do
  @moduledoc """
  Define module-level callbacks in models.

  A callback is invoked by `Ecto.Repo.Backend` before (or after) the event.

  If callbacks exist, everything (including the callbacks) will be wrapped
  in a transaction.

  ## Example

      defmodule User do
        use Ecto.Model.Callbacks

        after_create UserMailer, :send_welcome_email
        after_create Stats, :increase_user_count
      end

      defmodule UserMailer do
        def send_welcome_email(user)
          # send email to user
          user # important: return the user object
        end
      end

  When saving the user, the `Mailer.send_welcome_email/1` method is invoked with
  the user as param.

  Multiple callbacks can be defined, they will be invoked in order of invokation.

  ## Important

  As callbacks can be used to alter the user, please make sure to always return
  the user object, even when unaltered.

  Callbacks will not be invoked on bulk actions such as `Repo.delete_all` or
  `Repo.update_all`.

  """

  defmacro __using__(_opts) do
    quote do
      import Ecto.Model.Callbacks, except: [apply_callbacks: 2,
                                            register_callback: 4]
      @before_compile Ecto.Model.Callbacks
      @ecto_callbacks []
    end
  end

  @doc """
  Generates functions for all stored callbacks with the callback name.

  ## Example

  Given:

      defmodule User do
        # ....
        before_insert Module, :function
      end

  This macro generates the function `User.before_insert/1` that takes a user
  model and applies all before_insert callbacks to it.
  """
  defmacro __before_compile__(env) do
    module    = List.first(env.context_modules)
    callbacks = Module.get_attribute module, :ecto_callbacks

    for {event, callbacks} <- callbacks do
      quote unquote: true, bind_quoted: [event: event, callbacks: callbacks] do
        def unquote(event)(struct) do
          unquote(callbacks)
          |> Enum.reverse
          |> Enum.reduce struct, fn({mod, fun}, struct) ->
                                   apply(mod, fun, [struct])
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


  @doc """
  Registers a callback in a model by adding it to a list of callbacks stored
  in the module variable `@ecto_callbacks[event]`.
  """
  defp register_callback(event, module, function) do
    quote do
      event_callbacks =
        [ { unquote(module), unquote(function) } |
          List.wrap(@ecto_callbacks[unquote(event)]) ]

      ecto_callbacks =
        Keyword.put(@ecto_callbacks, unquote(event), event_callbacks)

      @ecto_callbacks ecto_callbacks
    end
  end

  @doc """
  Applies stored callbacks to a model.
  Checks wether the callback is defined on the model, returns the model
  unchanged if it isn't.

  ## Examples

      iex> Ecto.Model.Callbacks.apply_callbacks %User{}, :before_create
      %User{some_var: "has changed"}
  """
  def apply_callbacks(model, event) when is_map(model) do
    if defined?(model, [event]) do
      apply model.__struct__, event, [model]
    else
      model
    end
  end
  def apply_callbacks(object, _event), do: object

  def defined?(model, callbacks) when is_map(model) do
    module = model.__struct__
    Enum.all?(callbacks, &function_exported?(module, &1, 1))
  end
  def defined?(_model, _callbacks), do: false
end
