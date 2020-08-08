# For tasks/generators testing
Mix.start()
Mix.shell(Mix.Shell.Process)
System.put_env("ECTO_EDITOR", "")
Logger.configure(level: :info)

Code.require_file("support/test_repo.exs", __DIR__)
ExUnit.start()

if function_exported?(ExUnit, :after_suite, 1) do
  ExUnit.after_suite(fn _ -> Mix.shell(Mix.Shell.IO) end)
end

defmodule TestHelper do
  def discard_line_info(query_expr = %Ecto.Query.QueryExpr{}) do
    %Ecto.Query.QueryExpr{
      query_expr
      | line: -1
    }
  end

  def discard_line_info(query_expr_list) when is_list(query_expr_list) do
    query_expr_list |> Enum.map(&discard_line_info/1)
  end
end
