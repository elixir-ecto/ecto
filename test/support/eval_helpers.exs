defmodule Support.EvalHelpers do
  @doc """
  Delay the compilation of the code snippet so
  we can verify compile time behaviour.
  """
  defmacro quote_and_eval(quoted) do
    quoted = Macro.escape(quoted)
    quote do
      Code.eval_quoted(unquote(quoted), [], __ENV__)
    end
  end
end
