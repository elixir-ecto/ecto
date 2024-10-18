import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Comment do
  @moduledoc false

  alias Ecto.Query.Builder
  alias Ecto.Query.CommentExpr

  @spec escape(Macro.t(), Macro.Env.t()) :: Macro.t()
  def escape(comment, _env) when is_binary(comment), do: comment

  def escape(expr, env) do
    {expr, {_params, _acc}} =
      Builder.escape(expr, :any, {[], %{}}, [], env)

    expr
  end

  @doc """
  Called at runtime to assemble comment.
  """
  def comment!(query, comment, file, line) do
    comment = %CommentExpr{
      expr: comment,
      line: line,
      file: file
    }

    apply(query, comment)
  end

  def build(query, {:^, _, [var]}, env) do
    quote do
      Ecto.Query.Builder.Comment.comment!(
        unquote(query),
        unquote(var),
        unquote(env.file),
        unquote(env.line)
      )
    end
  end

  def build(query, comment, env) do
    Builder.apply_query(query, __MODULE__, [escape(comment, env)], env)
  end

  def build(query, comment, _file, _line) do
    apply(query, comment)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t(), String.t() | CommentExpr.t()) :: Ecto.Query.t()
  def apply(%Ecto.Query{comments: comments} = query, comment) do
    %{query | comments: comments ++ [comment]}
  end

  def apply(query, comment) do
    apply(Ecto.Queryable.to_query(query), comment)
  end
end
