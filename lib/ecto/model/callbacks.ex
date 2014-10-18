defmodule Ecto.Model.Callbacks do
  @events [:before_insert, :before_update, :before_delete,
           :after_get, :after_insert, :after_update, :after_delete]

  @moduledoc """
  Define module-level callbacks in models.

  A callback is invoked by `Ecto.Repo.Backend` before (or after) the event.

  ## Example

      defmodule User do
        use Ecto.Model.Callbacks

        after_create Mailer, :send_welcome_email
      end

      defmodule Mailer do
        def send_welcome_email(user)
          # send email to user
          user
        end
      end

  When saving the user, the `Mailer.send_welcome_email/1` method is invoked with
  the user as param.

  ## Important

  As callbacks can be used to alter the user, please make sure to always return
  the user object, even when unaltered.

  Callbacks will not be invoked on bulk actions such as `Repo.delete_all` or
  `Repo.update_all`.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @ecto_callbacks []

      import Ecto.Model.Callbacks, only: unquote(@events
                                                 |> Enum.map(&{&1, 2})
                                                 |> Keyword.new)

      def __callbacks__(_event), do: []
      Module.make_overridable(__MODULE__, [__callbacks__: 1])
    end
  end

  for event <- @events do
    @doc """
    Run callbacks on this event #{event}.

    ## Example

        iex> #{event} Module, :function
    """
    defmacro unquote(event)(module, function) do
      event = unquote(event)
      quote unquote: true, bind_quoted: [event: event] do
        Ecto.Model.Callbacks.register_callback(__MODULE__, event,
                                               unquote(module),
                                               unquote(function))
        def __callbacks__(event), do: Keyword.get_values(@ecto_callbacks, event)
        Module.make_overridable(__MODULE__, [__callbacks__: 1])
      end
    end
  end

  @doc false
  def register_callback(mod, name, callback_mod, callback_fun) do
    callbacks =
      Module.get_attribute(mod, :ecto_callbacks) ++
      Keyword.new([{name, {callback_mod, callback_fun}}])

    Module.put_attribute mod, :ecto_callbacks, callbacks
  end

  @doc """
  Applies stored callbacks to a model

  ## Examples

      iex> Ecto.Model.Callbacks.apply_callbacks %User{}, :before_create
      %User{}
  """
  def apply_callbacks(model, event) when is_map(model) do
    apply(model.__struct__, :__callbacks__, [event])
    |> Enum.reduce model, &do_apply_callback/2
  end
  def apply_callbacks(object, _event), do: object

  defp do_apply_callback({module, function}, model) do
    apply module, function, [model]
  end
end
