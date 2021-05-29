# For tasks/generators testing
Mix.start()
Mix.shell(Mix.Shell.Process)
System.put_env("ECTO_EDITOR", "")
Logger.configure(level: :info)
Code.require_file("support/test_repo.exs", __DIR__)

opts =
  if System.match?(System.version(), "< 1.11.0") do
    [exclude: [macro_to_string: true]]
  else
    []
  end

ExUnit.start(opts)

if function_exported?(ExUnit, :after_suite, 1) do
  ExUnit.after_suite(fn _ -> Mix.shell(Mix.Shell.IO) end)
end
