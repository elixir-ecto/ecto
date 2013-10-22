ExUnit.start

defmodule Ecto.TestCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__)
    end
  end

  def tmp_path do
    Path.expand("../test/tmp", __DIR__)
  end

  defmacro delay_compile(quoted) do
    quoted = Macro.escape(quoted)
    quote do
      Code.eval_quoted(unquote(quoted), [], __ENV__)
    end
  end

  defmacro in_tmp(fun) do
    quote do
      path = Path.join([Ecto.TestCase.tmp_path,
                        inspect(__ENV__.module),
                        elem(__ENV__.function, 0)])

      File.rm_rf!(path)
      File.mkdir_p!(path)
      File.cd!(path, fn -> unquote(fun).(path) end)
    end
  end
end
