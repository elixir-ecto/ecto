# For tasks/generators testing
Mix.start()
Mix.shell(Mix.Shell.Process)
System.put_env("ECTO_EDITOR", "")

# Ensure Query API is loaded
Code.ensure_loaded(Ecto.Query.API)

# Commonly used support feature
Code.require_file "support/file_helpers.exs", __DIR__
Code.require_file "support/compile_helpers.exs", __DIR__

ExUnit.start()
