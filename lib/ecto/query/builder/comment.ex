import Kernel, except: [apply: 3]

defmodule Ecto.Query.Builder.Comment do
  @moduledoc false

  alias Ecto.Query.Builder

  # A comment is rendered verbatim inside a `/* ... */` SQL comment, so the only
  # way for its text to escape into executable SQL is to manipulate the comment
  # delimiters. Reject `*/` (closes the block early) and `/*` (opens a nested
  # block that, where comments nest, swallows the closing `*/`), plus null bytes.
  @forbidden ["*/", "/*", <<0>>]

  @doc """
  Escapes the comment text.

      iex> escape("my-query")
      "my-query"

  """
  @spec escape(Macro.t()) :: Macro.t()
  def escape(comment) when is_binary(comment) do
    if String.contains?(comment, @forbidden) do
      Builder.error!(
        "a comment cannot contain `/*`, `*/`, or null bytes, got: `#{comment}`. "
      )
    end

    comment
  end

  def escape({:^, _, [_]}) do
    Builder.error!(
      "interpolation is not allowed in a query comment. " <>
        "Comments must be compile-time literal strings so they stay a bounded set " <>
        "and remain safe to cache. For dynamic comments use the `:comments` repo option"
    )
  end

  def escape(other) do
    Builder.error!("`#{Macro.to_string(other)}` is not a valid comment, it must be a literal string")
  end

  @doc """
  Builds a quoted expression that appends a `{position, comment}` to the query.
  """
  @spec build(:pre | :post, Macro.t(), Macro.t(), Macro.Env.t()) :: Macro.t()
  def build(position, query, expr, env) do
    Builder.apply_query(query, __MODULE__, [position, escape(expr)], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t(), :pre | :post, term) :: Ecto.Query.t()
  def apply(%Ecto.Query{} = query, position, value) do
    %{query | comments: query.comments ++ [{position, value}]}
  end

  def apply(query, position, value) do
    apply(Ecto.Queryable.to_query(query), position, value)
  end
end
