defmodule Ecto.Model.Callbacks do
  @moduledoc """
  Define module-level callbacks in models.

  ## Lifecycle callbacks

  Ecto provides lifecycle callbacks around insert, update
  and delete commands.

  A callback is invoked by your `Ecto.Repo` before (or after)
  particular events. Lifecycle callbacks always receive a
  changeset as an argument and must always return a modified changeset.

  Such callbacks are useful for data consistency: keeping
  counters, setting field values and so on. For this reason,
  callbacks:

    * cannot abort
    * run inside the transaction (if supported by the database/adapter)
    * are invoked only after the data is validated

  Therefore, don't use callbacks for validation, enforcing business
  rules or performing actions unrelated to the data itself, like
  sending e-mails.

  Finally keep in mind callbacks are not invoked on bulk actions
  such as `Ecto.Repo.update_all/3` or `Ecto.Repo.delete_all/2`.

  ## Other callbacks

  Besides lifecycle callbacks, Ecto also supports an `after_load`
  callback that is invoked everytime a model is loaded with the
  model itself. See `after_load/2` for more informations.

  ## Examples

      defmodule User do
        use Ecto.Model.Callbacks

        after_insert :increase_user_count

        def increase_user_count(changeset) do
          # ...
        end
      end

  When creating the user, the `after_insert` callbacks will be
  invoked with a changeset as argument. Multiple callbacks
  can be defined, they will be invoked in order of declaration.

  A callback can be defined in the following formats:

      # Invoke the local function increase_user_count/1
      after_insert :increase_user_count

      # Invoke the local function increase_user_count/3
      # with the given arguments (changeset is prepended)
      after_insert :increase_user_count, ["foo", "bar"]

      # Invoke the remote function Stats.increase_user_count/1
      after_insert Stats, :increase_user_count

      # Invoke the remote function Stats.increase_user_count/3
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

  The callback must return a changeset and always runs inside
  a transaction.

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
  At this point, the changeset has already been validated and is
  always valid.

  The callback must return a changeset and always runs inside
  a transaction.

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

  The callback must return a changeset and always runs inside
  a transaction.

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
  changeset has already been validated and is always valid.

  The callback must return a changeset and always runs inside
  a transaction.

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
  stored in it.

  The callback must return a changeset and always runs inside
  a transaction.

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
    do: register_callback(:after_load, function, args, [])

  @doc """
  Same as `after_load/2` but with arguments.
  """
  defmacro after_load(module, function, args),
    do: register_callback(:after_load, module, function, args)

  defp register_callback(event, module, function, args) do
    quote bind_quoted: binding() do
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
