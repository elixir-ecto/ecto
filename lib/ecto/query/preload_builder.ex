defmodule Ecto.Query.PreloadBuilder do
  @moduledoc false
  alias Ecto.Query.BuilderUtil

  @type preload :: [preload] | [{ atom, preload }]

  @doc """
  Escapes a preload.

  A preload may be an atom, a list of atoms or a keyword list.
  """
  @spec escape(term) :: preload | no_return
  def escape(list) when is_list(list) do
    Enum.map(list, &escape/1)
  end

  def escape({ atom, list }) when is_atom(atom) do
    { atom, escape(list) }
  end

  def escape(atom) when is_atom(atom) do
    [atom]
  end

  def escape(other) do
    raise Ecto.QueryError,
      reason: "preload expects a compile time a atom, a (nested) keyword or " <>
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
    preload = Ecto.Query.QueryExpr[expr: escape(expr), file: env.file, line: env.line]
    BuilderUtil.apply_query(query, __MODULE__, [preload], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.Query.t
  def apply(query, expr) do
    Ecto.Query.Query[preloads: preloads] = query = Ecto.Queryable.to_query(query)
    query.preloads(preloads ++ [expr])
  end
end
