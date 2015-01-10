defmodule Ecto.Model.Callbacks do
  @moduledoc """
  Define module-level callbacks in models.

  A callback is invoked by your `Ecto.Repo` before (or after)
  particular events. A callback must always return the given
  data structure and they always run inside a transaction.

  ## Example

      defmodule User do
        use Ecto.Model.Callbacks

        after_insert Stats, :increase_user_count

        def increase_user_count(user)
          # ...
        end
      end

  When creating the user, the `after_insert` callbacks will be
  invoked with the `user` struct as argument. Multiple callbacks
  can be defined, they will be invoked in order of declaration.

  ## Usage

  Callbacks in Ecto are useful for data consistency, for keeping
  counters, setting fields and so on. Avoid using callbacks for
  business rules or doing actions unrelated to the data itself,
  like sending e-mails.

  Finally, keep in mind callbacks are not invoked on bulk actions
  such as `Repo.delete_all` or `Repo.update_all`.
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

  The callback receives a `Ecto.Changeset` and must return a changeset.

  ## Example

      before_insert User, :generate_permalink

  """
  defmacro before_insert(module, function),
    do: register_callback(:before_insert, module, function)

  @doc """
  Adds a callback to the model that is invoked after the model is inserted
  into the database.

  The callback receives a `Ecto.Changeset` and must return a changeset.

  ## Example

      after_insert Stats, :increase_user_count

  """
  defmacro after_insert(module, function),
    do: register_callback(:after_insert, module, function)

  @doc """
  Adds a callback to the model that is invoked before the model is updated.

  The callback receives a `Ecto.Changeset` and must return a changeset.

  ## Example

    before_update User, :set_update_at_timestamp

  """
  defmacro before_update(module, function),
    do: register_callback(:before_update, module, function)

  @doc """
  Adds a callback to the model that is invoked after the model is updated.

  The callback receives a `Ecto.Changeset` and must return a changeset.

  ## Example

      after_update User, :notify_account_change

  """
  defmacro after_update(module, function),
    do: register_callback(:after_update, module, function)

  @doc """
  Adds a callback to the model that is invoked before the model is deleted
  from the database.

  The callback receives the model being deleted and must return such model.

  ## Example

      before_delete User, :copy_to_archive

  """
  defmacro before_delete(module, function),
    do: register_callback(:before_delete, module, function)

  @doc """
  Adds a callback to the model that is invoked before the model is deleted
  from the database.

  The callback receives the model being deleted and must return such model.

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
  Applies stored callbacks in model to given data.

  Checks wether the callback is defined on the model,
  returns the data unchanged if it isn't.

  This function also validates if the struct given
  as input to the callback is the same as in the output.

  ## Examples

      iex> Ecto.Model.Callbacks.__apply__ User, :before_delete, %User{}
      %User{some_var: "has changed"}

  """
  def __apply__(module, callback, %{__struct__: expected} = data) do
    if function_exported?(module, callback, 1) do
      case apply(module, callback, [data]) do
        %{__struct__: ^expected} = data ->
          data
        other ->
          raise ArgumentError,
            "expected `#{callback}` callbacks to return a #{inspect expected}, got: #{inspect other}"
      end
    else
      data
    end
  end
end
