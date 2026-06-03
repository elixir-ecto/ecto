import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Label do
  @moduledoc false

  alias Ecto.Query.Builder

  @forbidden ["*/", "/*", <<0>>]

  @doc """
  Escapes the label text.

      iex> escape(quote(do: "my-query"))
      "my-query"

  """
  @spec escape(Macro.t()) :: Macro.t()
  def escape(label) when is_binary(label) do
    if String.contains?(label, @forbidden) do
      Builder.error!(forbidden_message(label))
    end

    label
  end

  def escape({:^, _, [expr]}) do
    quote do
      Ecto.Query.Builder.Label.runtime!(unquote(expr))
    end
  end

  def escape(other) do
    Builder.error!(
      "`#{Macro.to_string(other)}` is not a valid label. " <>
        "For security reasons, a label must be a literal string or an interpolated string"
    )
  end

  @doc """
  Validates a label given at runtime via interpolation.
  """
  @spec runtime!(term) :: String.t()
  def runtime!(label) when is_binary(label) do
    if String.contains?(label, @forbidden) do
      raise ArgumentError, forbidden_message(label)
    end

    label
  end

  def runtime!(other) do
    raise ArgumentError, "a label must be a string, got: `#{inspect(other)}`"
  end

  defp forbidden_message(label) do
    "a label cannot contain `/*`, `*/`, or null bytes, got: `#{inspect(label)}`. "
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t(), Macro.t(), Macro.Env.t()) :: Macro.t()
  def build(query, expr, env) do
    Builder.apply_query(query, __MODULE__, [escape(expr)], env)
  end

  @doc """
  The callback applied by `build/3` to build the query.
  """
  @spec apply(Ecto.Queryable.t(), term) :: Ecto.Query.t()
  def apply(%Ecto.Query{} = query, value) do
    %{query | label: value}
  end

  def apply(query, value) do
    apply(Ecto.Queryable.to_query(query), value)
  end
end
