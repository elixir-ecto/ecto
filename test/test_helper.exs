ExUnit.start

defmodule Ecto.TestHelpers do
  defmacro delay_compile(quoted) do
    quoted = Macro.escape(quoted)
    quote do
      Code.eval_quoted(unquote(quoted), [], __ENV__)
    end
  end
end
