import Kernel, except: [apply: 3]

defmodule Ecto.Query.Builder.Comment do
  @moduledoc false

  alias Ecto.Query.Builder

  # A comment is rendered verbatim inside a `/* ... */` SQL comment, so the only
  # way for its text to escape into executable SQL is to manipulate the comment
  # delimiters. Reject `*/` (closes the block early) and `/*` (opens a nested
  # block that, where comments nest, swallows the closing `*/`), plus null bytes.
  @forbidden ["*/", "/*", <<0>>]

  # Placed right after `/*`, these prefixes would form MySQL/MariaDB executable
  # comments (`/*!...*/`, `/*M!...*/`) or optimizer hints (`/*+...*/`), turning
  # the comment into SQL that executes.
  @forbidden_prefixes ["!", "+", "M!"]

  @doc """
  Validates the comment text, returning it unchanged.

      iex> validate!("my-query")
      "my-query"

  """
  @spec validate!(Macro.t()) :: Macro.t()
  def validate!(comment) when is_binary(comment) do
    if String.contains?(comment, @forbidden) do
      Builder.error!("a comment cannot contain `/*`, `*/`, or null bytes, got: `#{comment}`")
    end

    if String.starts_with?(comment, @forbidden_prefixes) do
      Builder.error!(
        "a comment cannot start with `!`, `+`, or `M!`, as MySQL and MariaDB " <>
          "treat such comments as executable SQL or optimizer hints, got: `#{comment}`"
      )
    end

    comment
  end

  def validate!({:^, _, [_]}) do
    Builder.error!(
      "interpolation is not allowed in a query comment. " <>
        "Comments must be compile-time literal strings so they stay a bounded set " <>
        "and remain safe to cache. For dynamic comments use the `:comments` repo option"
    )
  end

  def validate!(other) do
    Builder.error!("`#{Macro.to_string(other)}` is not a valid comment, it must be a literal string")
  end

  @doc """
  Builds a quoted expression that appends a `{position, comment}` to the query.
  """
  @spec build(:pre | :post, Macro.t(), Macro.t(), Macro.Env.t()) :: Macro.t()
  def build(position, query, expr, env) do
    Builder.apply_query(query, __MODULE__, [position, validate!(expr)], env)
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
