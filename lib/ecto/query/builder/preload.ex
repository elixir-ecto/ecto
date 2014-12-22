defmodule Ecto.Query.Builder.Preload do
  @moduledoc false
  alias Ecto.Query.Builder

  @doc """
  Escapes a preload.

  A preload may be an atom, a list of atoms or a keyword list
  nested as a rose tree.

      iex> escape(:foo)
      :foo

      iex> escape(foo: :bar)
      [foo: :bar]

  """
  @spec escape(Macro.t) :: Macro.t | no_return
  def escape(atom) when is_atom(atom),
    do: atom

  def escape(list) when is_list(list),
    do: Enum.map(list, &escape_each/1)

  def escape({:^, _, [expr]}),
    do: expr

  def escape(other) do
    Builder.error! "`#{Macro.to_string other}` is not a valid preload expression. " <>
                   "preload expects an atom, a (nested) keyword or a (nested) " <>
                   "list of atoms. Use ^ if you want to interpolate a value"
  end

  defp escape_each({atom, list}) when is_atom(atom),
    do: {atom, escape(list)}
  defp escape_each(other),
    do: escape(other)

  @doc """
  Applies the preloaded value into the query.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, Macro.t, Macro.Env.t) :: Macro.t
  def build(query, expr, env) do
    Builder.apply_query(query, __MODULE__, [escape(expr)], env)
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
