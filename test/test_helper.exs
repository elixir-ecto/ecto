Mix.start()
Mix.shell(Mix.Shell.Process)

ExUnit.start()

defmodule Ecto.TestCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__)
    end
  end

  @doc """
  Returns the `tmp_path` for tests.
  """
  def tmp_path do
    Path.expand("../test/tmp", __DIR__)
  end

  @doc """
  Delay the compilation of the code snippet so
  we can verify compile time behaviour.
  """
  defmacro delay_compile(quoted) do
    quoted = Macro.escape(quoted)
    quote do
      Code.eval_quoted(unquote(quoted), [], __ENV__)
    end
  end

  @doc """
  Executes the given function in a temp directory
  tailored for this test case and test.
  """
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

  @doc """
  Asserts a file was generated.
  """
  def assert_file(file) do
    assert File.regular?(file), "Expected #{file} to exist, but does not"
  end

  @doc """
  Asserts a file was generated and that it matches a given pattern.
  """
  def assert_file(file, match) when is_regex(match) do
    assert_file file, &(&1 =~ match)
  end

  def assert_file(file, callback) when is_function(callback, 1) do
    assert_file(file)
    callback.(File.read!(file))
  end
end
