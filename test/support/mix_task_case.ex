defmodule Ecto.MixTaskCase do
  use ExUnit.CaseTemplate

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)
    :ok
  end
end
