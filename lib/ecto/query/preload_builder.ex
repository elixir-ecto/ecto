defmodule Ecto.Query.PreloadBuilder do
  @moduledoc false
  alias Ecto.Query.BuilderUtil

  @type preload :: [{atom, preload}]

  @doc """
  Normalizes a preload.

  A preload may be an atom, a list of atoms or a keyword list
  nested as a rose tree.
  """
  @spec normalize(term) :: preload | no_return
  def normalize(preload) do
    Enum.map(List.wrap(preload), &normalize_each/1)
  end

  defp normalize_each({atom, list}) when is_atom(atom) do
    {atom, normalize(list)}
  end

  defp normalize_each(atom) when is_atom(atom) do
    {atom, []}
  end

  defp normalize_each(other) do
    raise Ecto.QueryError,
      reason: "preload expects an atom, a (nested) keyword or " <>
              "a (nested) list of atoms, got: #{inspect other}"
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, Macro.t, Macro.Env.t) :: Macro.t
  def build(query, expr, env) do
    expr = normalize(expr)
    preload = quote do: %Ecto.Query.QueryExpr{expr: unquote(expr),
                          file: unquote(env.file), line: unquote(env.line)}
    BuilderUtil.apply_query(query, __MODULE__, [preload], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(query, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | preloads: query.preloads ++ [expr]}
  end
end
