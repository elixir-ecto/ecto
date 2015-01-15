defmodule Ecto.Model.Callbacks do
  @moduledoc """
  Define module-level callbacks in models.

  A callback is invoked by your `Ecto.Repo` before (or after)
  particular events. Callbacks receive changesets, must
  always return a changeset back and always run inside a transaction.

  Callbacks in Ecto are useful for data consistency, like keeping
  counters, setting field values and so on. For this reason, callbacks
  cannot abort and are invoked after the data is validated.

  Therefore, don't use callbacks for validation, enforcing business
  rules or performing actions unrelated to the data itself, like
  sending e-mails.

  Finally keep in mind callbacks are not invoked on bulk actions
  such as `Ecto.Repo.update_all/3` or `Ecto.Repo.delete_all/2`.

  ## Example

      defmodule User do
        use Ecto.Model.Callbacks

        after_insert Stats, :increase_user_count

        def increase_user_count(changeset)
          # ...
        end
      end

  When creating the user, the `after_insert` callbacks will be
  invoked with a changeset as argument. Multiple callbacks
  can be defined, they will be invoked in order of declaration.

  A callback can be defined in the following formats:

      # Invoke the local function increase_user_count
      after_insert :increase_user_count

      # Invoke the local function increase_user_count
      # with the given arguments (changeset is prepended)
      after_insert :increase_user_count, ["foo", "bar"]

      # Invoke the remote function increase_user_count
      after_insert Stats, :increase_user_count

      # Invoke the remote function increase_user_count
      # with the given arguments (changeset is prepended)
      after_insert Stats, :increase_user_count, ["foo", "bar"]

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
  are sent to the repository, the callback will receive an
  `Ecto.Changeset` with all the model fields and changes in
  the `changeset.changes` field. At this point, the changeset
  was already validated and is always valid.

  The callback must return a changeset.

  ## Example

      before_insert User, :generate_permalink

  """
  defmacro before_insert(function, args \\ []),
    do: register_callback(:before_insert, function, args, [])

  @doc """
  Same as `before_insert/2` but with arguments.
  """
  defmacro before_insert(module, function, args),
    do: register_callback(:before_insert, module, function, args)

  @doc """
  Adds a callback that is invoked after the model is inserted
  into the repository.

  The callback receives an `Ecto.Changeset` with both repository
  values and changeset changes already applied to the model.
  The callback must return a changeset.

  ## Example

      after_insert Stats, :increase_user_count

  """
  defmacro after_insert(function, args \\ []),
    do: register_callback(:after_insert, function, args, [])

  @doc """
  Same as `after_insert/2` but with arguments.
  """
  defmacro after_insert(module, function, args),
    do: register_callback(:after_insert, module, function, args)

  @doc """
  Adds a callback that is invoked before the model is updated.

  The callback receives an `Ecto.Changeset` with the changes
  to be sent to the database in the `changeset.changes` field.
  At this point, the changeset was already validated and is
  always valid.

  The callback must return a changeset.

  ## Example

    before_update User, :set_update_at_timestamp

  """
  defmacro before_update(function, args \\ []),
    do: register_callback(:before_update, function, args, [])

  @doc """
  Same as `before_update/2` but with arguments.
  """
  defmacro before_update(module, function, args),
    do: register_callback(:before_update, module, function, args)

  @doc """
  Adds a callback that is invoked after the model is updated.

  The callback receives an `Ecto.Changeset` with both repository
  values and changeset changes already applied to the model.
  The callback must return a changeset.

  ## Example

      after_update User, :notify_account_change

  """
  defmacro after_update(function, args \\ []),
    do: register_callback(:after_update, function, args, [])

  @doc """
  Same as `after_update/2` but with arguments.
  """
  defmacro after_update(module, function, args),
    do: register_callback(:after_update, module, function, args)

  @doc """
  Adds a callback that is invoked before the model is deleted
  from the repository.

  The callback receives an `Ecto.Changeset`. At this point, the
  changeset was already validated and is always valid.

  The callback must return a changeset.

  ## Example

      before_delete User, :copy_to_archive

  """
  defmacro before_delete(function, args \\ []),
    do: register_callback(:before_delete, function, args, [])

  @doc """
  Same as `before_delete/2` but with arguments.
  """
  defmacro before_delete(module, function, args),
    do: register_callback(:before_delete, module, function, args)

  @doc """
  Adds a callback that is invoked before the model is deleted
  from the repository.

  The callback receives an `Ecto.Changeset` with the model
  stored in it. The callback must return a changeset.

  ## Example

      after_delete User, :notify_garbage_collectors

  """
  defmacro after_delete(function, args \\ []),
    do: register_callback(:after_delete, function, args, [])

  @doc """
  Same as `after_delete/2` but with arguments.
  """
  defmacro after_delete(module, function, args),
    do: register_callback(:after_delete, module, function, args)

  defp register_callback(event, module, function, args) do
    quote bind_quoted: binding() do
      callback = {module, function, args}
      @ecto_callbacks Map.update(@ecto_callbacks, event, [callback], &[callback|&1])
    end
  end

  defp compile_callback({function, args, []}, acc)
      when is_atom(function) and is_list(args) do
    error = callback_error("#{function}/#{length(args)+1}")

    quote do
      case unquote(function)(unquote(acc), unquote_splicing(Macro.escape(args))) do
        %Ecto.Changeset{} = changeset -> changeset
        other -> raise unquote(error) <> inspect(other)
      end
    end
  end

  defp compile_callback({module, function, args}, acc)
      when is_atom(module) and is_atom(function) and is_list(args) do
    error = callback_error("#{inspect module}.#{function}/#{length(args)+1}")

    quote do
      case unquote(module).unquote(function)(unquote(acc), unquote_splicing(Macro.escape(args))) do
        %Ecto.Changeset{} = changeset -> changeset
        other -> raise unquote(error) <> inspect(other)
      end
    end
  end

  defp callback_error(callback) do
    "expected callback #{callback} to return an Ecto.Changeset, got: "
  end

  @doc """
  Applies stored callbacks in model to given data.

  Checks wether the callback is defined on the model,
  returns the data unchanged if it isn't.

  This function expects a changeset as input.

  ## Examples

      iex> changeset = Ecto.Changeset.cast(params, %User{}, ~w(name), ~w())
      iex> Ecto.Model.Callbacks.__apply__ User, :before_delete, changeset
      %Ecto.Changeset{...}

  """
  def __apply__(module, callback, %Ecto.Changeset{} = changeset) do
    if function_exported?(module, callback, 1) do
      apply(module, callback, [changeset])
    else
      changeset
    end
  end
end
