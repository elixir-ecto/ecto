# For tasks/generators testing
Mix.start()
Mix.shell(Mix.Shell.Process)
System.put_env("ECTO_EDITOR", "")
Logger.configure(level: :info)
Code.require_file("support/test_repo.exs", __DIR__)

ExUnit.start()
ExUnit.after_suite(fn _ -> Mix.shell(Mix.Shell.IO) end)
