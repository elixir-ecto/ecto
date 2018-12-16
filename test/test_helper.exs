# For tasks/generators testing
Mix.start()
Mix.shell(Mix.Shell.Process)
System.put_env("ECTO_EDITOR", "")
Logger.configure(level: :info)

defmodule Ecto.Integration.AdapterTypes do
  # Builtin uuid type is Ecto.UUID, many adapters will use it, but some may use
  # it own implmentation.
  def uuid, do: Ecto.UUID
end

Code.require_file "support/test_repo.exs", __DIR__
ExUnit.start()

if function_exported?(ExUnit, :after_suite, 1) do
  ExUnit.after_suite(fn _ -> Mix.shell(Mix.Shell.IO) end)
end
