# TODO delete this file
defmodule Debug do
  defmacro binding() do
    quote do
      IO.inspect(binding(), label: Debug.label(__ENV__), charlists: :as_lists)
    end
  end

  defmacro unstruct(term) do
    quote do
      IO.inspect(unquote(term), label: Debug.label(__ENV__), charlists: :as_lists, structs: false)
    end
  end

  defmacro inspect(term) do
    quote do
      IO.inspect(unquote(term), label: Debug.label(__ENV__), charlists: :as_lists)
    end
  end

  def label(env) do
    {fun, arity} = env.function
    "#{env.module}.#{fun}/#{arity} #{env.line}"
  end
end
