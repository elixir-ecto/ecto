# For tasks/generators testing
Mix.start()
Mix.shell(Mix.Shell.Process)
System.put_env("ECTO_EDITOR", "")

# Commonly used support feature
Code.require_file "support/file_helpers.exs", __DIR__
Code.require_file "support/eval_helpers.exs", __DIR__
Code.require_file "support/mock_adapter.exs", __DIR__
Code.require_file "support/mock_repo.exs", __DIR__

ExUnit.start()
