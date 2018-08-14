# For tasks/generators testing
Mix.start()
System.put_env("ECTO_EDITOR", "")
Logger.configure(level: :info)

Code.require_file "../../integration_test/support/file_helpers.exs", __DIR__
ExUnit.start()
