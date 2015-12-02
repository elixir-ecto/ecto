defmodule Ecto.Model.Callbacks do
  @moduledoc """
  Warning: Ecto callbacks are deprecated.
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
      body = Enum.reduce Enum.reverse(callbacks),
                         quote(do: changeset), &compile_callback/2

      quote do
        def unquote(event)(changeset), do: unquote(body)
      end
    end
  end

  # Callback macros

  @doc """
  Adds a callback that is invoked before the model is inserted
  into the repository.

  Since on insert all the model fields plus changeset changes
  are sent to the repository, the callback receives an
  `Ecto.Changeset` with all the model fields and changes in
  the `changeset.changes` field. At this point, the changeset
  has already been validated and is always valid.

  The callback must return a changeset and always runs inside
  a transaction.

  ## Example

      before_insert User, :generate_permalink

  """
  defmacro before_insert(function, args \\ []),
    do: register_callback(:before_insert, function, args, [], __CALLER__)

  @doc """
  Same as `before_insert/2` but with arguments.
  """
  defmacro before_insert(module, function, args),
    do: register_callback(:before_insert, module, function, args, __CALLER__)

  @doc """
  Adds a callback that is invoked after the model is inserted
  into the repository.

  The callback receives an `Ecto.Changeset` with both repository
  values and changeset changes already applied to the model.

  The callback must return a changeset and always runs inside
  a transaction.

  ## Example

      after_insert Stats, :increase_user_count

  """
  defmacro after_insert(function, args \\ []),
    do: register_callback(:after_insert, function, args, [], __CALLER__)

  @doc """
  Same as `after_insert/2` but with arguments.
  """
  defmacro after_insert(module, function, args),
    do: register_callback(:after_insert, module, function, args, __CALLER__)

  @doc """
  Adds a callback that is invoked before the model is updated.

  The callback receives an `Ecto.Changeset` with the changes
  to be sent to the database in the `changeset.changes` field.
  At this point, the changeset has already been validated and is
  always valid.

  The callback must return a changeset and always runs inside
  a transaction.

  ## Example

      before_update User, :set_update_at_timestamp

  """
  defmacro before_update(function, args \\ []),
    do: register_callback(:before_update, function, args, [], __CALLER__)

  @doc """
  Same as `before_update/2` but with arguments.
  """
  defmacro before_update(module, function, args),
    do: register_callback(:before_update, module, function, args, __CALLER__)

  @doc """
  Adds a callback that is invoked after the model is updated.

  The callback receives an `Ecto.Changeset` with both repository
  values and changeset changes already applied to the model.

  The callback must return a changeset and always runs inside
  a transaction.

  ## Example

      after_update User, :notify_account_change

  """
  defmacro after_update(function, args \\ []),
    do: register_callback(:after_update, function, args, [], __CALLER__)

  @doc """
  Same as `after_update/2` but with arguments.
  """
  defmacro after_update(module, function, args),
    do: register_callback(:after_update, module, function, args, __CALLER__)

  @doc """
  Adds a callback that is invoked before the model is deleted
  from the repository.

  The callback receives an `Ecto.Changeset`. At this point, the
  changeset has already been validated and is always valid.

  The callback must return a changeset and always runs inside
  a transaction.

  ## Example

      before_delete User, :copy_to_archive

  """
  defmacro before_delete(function, args \\ []),
    do: register_callback(:before_delete, function, args, [], __CALLER__)

  @doc """
  Same as `before_delete/2` but with arguments.
  """
  defmacro before_delete(module, function, args),
    do: register_callback(:before_delete, module, function, args, __CALLER__)

  @doc """
  Adds a callback that is invoked after the model is deleted
  from the repository.

  The callback receives an `Ecto.Changeset` with the model
  stored in it.

  The callback must return a changeset and always runs inside
  a transaction.

  ## Example

      after_delete User, :notify_garbage_collectors

  """
  defmacro after_delete(function, args \\ []),
    do: register_callback(:after_delete, function, args, [], __CALLER__)

  @doc """
  Same as `after_delete/2` but with arguments.
  """
  defmacro after_delete(module, function, args),
    do: register_callback(:after_delete, module, function, args, __CALLER__)

  @doc """
  Adds a callback that is invoked after the model is loaded
  from the repository.

  The callback receives the model being loaded and must
  return a model.

  This callback can be useful to resolve the value of virtual
  fields in situations they must always be present in the model.
  Since this will be invoked every time the model is loaded, the
  callback must execute very quickly to avoid drastic perfomance
  hits.

  Another common misuse of `after_load` callbacks is to use it
  for loading fields which are not always required. For example,
  imagine you need to generate an access token based on the `User`
  id and password. One could use `after_load` and a virtual field
  to precompute the `access_token` value but it is simpler and cleaner
  to simply provide an `access_token` function in the model:

      User.access_token(user)

  ## Example

      after_load Post, :set_permalink

  """
  defmacro after_load(function, args \\ []),
    do: register_callback(:after_load, function, args, [], __CALLER__)

  @doc """
  Same as `after_load/2` but with arguments.
  """
  defmacro after_load(module, function, args),
    do: register_callback(:after_load, module, function, args, __CALLER__)

  defp register_callback(event, module, function, args, caller) do
    IO.write :stderr, "warning: #{event} is deprecated\n" <>
                      Exception.format_stacktrace(Macro.Env.stacktrace(caller))
    quote bind_quoted: [event: event, module: module, function: function, args: args] do
      callback = {module, function, args}
      @ecto_callbacks Map.update(@ecto_callbacks, event, [callback], &[callback|&1])
    end
  end

  defp compile_callback({function, args, []}, acc)
      when is_atom(function) and is_list(args) do
    quote do
      unquote(function)(unquote(acc), unquote_splicing(Macro.escape(args)))
    end
  end

  defp compile_callback({module, function, args}, acc)
      when is_atom(module) and is_atom(function) and is_list(args) do
    quote do
      unquote(module).unquote(function)(unquote(acc), unquote_splicing(Macro.escape(args)))
    end
  end

  @doc """
  Applies stored callbacks in model to given data.

  Checks whether the callback is defined on the model,
  returns the data unchanged if it isn't.

  This function expects a changeset for all callbacks except after_load as input.

  ## Examples

      iex> changeset = Ecto.Changeset.cast(params, %User{}, ~w(name), ~w())
      iex> Ecto.Model.Callbacks.__apply__ User, :before_delete, changeset
      %Ecto.Changeset{...}

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
