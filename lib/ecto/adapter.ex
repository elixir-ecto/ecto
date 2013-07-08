defmodule Ecto.Adapter do
  use Behaviour

  # defcallback __using__(term()) :: term()
  defcallback start(atom()) :: :ok | { :error, term() }
  defcallback query(atom(), term()) :: { :ok, term() } | { :error, term() }
  # defcallback query!(atom(), term()) :: term() | no_return
  # defcallback create(atom(), term()) :: :ok | { :error, term() }
  # defcallback create!(atom(), term()) :: :ok | no_return
end
