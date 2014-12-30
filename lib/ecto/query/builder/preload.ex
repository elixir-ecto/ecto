defmodule Ecto.Query.Builder.Preload do
  @moduledoc false
  alias Ecto.Query.Builder

  @doc """
  Escapes a preload.

  A preload may be an atom, a list of atoms or a keyword list
  nested as a rose tree.

      iex> escape(:foo, [])
      {[:foo], []}

      iex> escape([foo: :bar], [])
      {[foo: [:bar]], []}

      iex> escape([foo: [:bar, bar: :bat]], [])
      {[foo: [:bar, bar: [:bat]]], []}

      iex> escape([foo: {:^, [], ["external"]}], [])
      {[foo: ["external"]], []}

      iex> escape([foo: [:bar, {:^, [], ["external"]}], baz: :bat], [])
      {[foo: [:bar, "external"], baz: [:bat]], []}

      iex> escape([foo: {:c, [], nil}], [c: 1])
      {[], [foo: {1, []}]}

      iex> escape([foo: {{:c, [], nil}, bar: {:l, [], nil}}], [c: 1, l: 2])
      {[], [foo: {1, [bar: {2, []}]}]}

      iex> escape([foo: {:c, [], nil}, bar: {:l, [], nil}], [c: 1, l: 2])
      {[], [foo: {1, []}, bar: {2, []}]}

      iex> escape([foo: {{:c, [], nil}, :bar}], [c: 1])
      ** (Ecto.Query.CompileError) cannot preload `:bar` inside join association preload

      iex> escape([foo: [bar: {:c, [], nil}]], [c: 1])
      ** (Ecto.Query.CompileError) cannot preload join association `:bar` with binding `c` because parent preload is not a join association

  """
  @spec escape(Macro.t, Keyword.t) :: {[Macro.t], [Macro.t]} | no_return
  def escape(preloads, vars) do
    {preloads, assocs} = escape(preloads, :both, [], [], vars)
    {Enum.reverse(preloads), Enum.reverse(assocs)}
  end

  defp escape(atom, mode, preloads, assocs, _vars) when is_atom(atom) do
    assert_preload!(mode, atom)
    {[atom|preloads], assocs}
  end

  defp escape(list, mode, preloads, assocs, vars) when is_list(list) do
    Enum.reduce list, {preloads, assocs}, fn item, acc ->
      escape_each(item, mode, acc, vars)
    end
  end

  defp escape({:^, _, [inner]} = expr, mode, preloads, assocs, _vars) do
    assert_preload!(mode, expr)
    {[inner|preloads], assocs}
  end

  defp escape(other, _mode, _preloads, _assocs, _vars) do
    Builder.error! "`#{Macro.to_string other}` is not a valid preload expression. " <>
                   "preload expects an atom, a (nested) list of atoms or a (nested) " <>
                   "keyword list with a binding, atoms or lists as values. " <>
                   "Use ^ if you want to interpolate a value"
  end

  defp escape_each({atom, {var, _, context}}, mode, {preloads, assocs}, vars)
      when is_atom(atom) and is_atom(context) do
    assert_assoc!(mode, atom, var)
    idx = Builder.find_var!(var, vars)
    {preloads, [{atom, {idx, []}}|assocs]}
  end

  defp escape_each({atom, {{var, _, context}, list}}, mode, {preloads, assocs}, vars)
      when is_atom(atom) and is_atom(context) do
    assert_assoc!(mode, atom, var)
    idx = Builder.find_var!(var, vars)
    {[], inner_assocs} = escape(list, :assoc, [], [], vars)
    {preloads,
     [{atom, {idx, Enum.reverse(inner_assocs)}}|assocs]}
  end

  defp escape_each({atom, list}, mode, {preloads, assocs}, vars) when is_atom(atom) do
    assert_preload!(mode, {atom, list})
    {inner_preloads, []} = escape(list, :preload, [], [], vars)
    {[{atom, Enum.reverse(inner_preloads)}|preloads], assocs}
  end

  defp escape_each(other, mode, {preloads, assocs}, vars) do
    escape(other, mode, preloads, assocs, vars)
  end

  defp assert_assoc!(mode, _atom, _var) when mode in [:both, :assoc], do: :ok
  defp assert_assoc!(_mode, atom, var) do
    Builder.error! "cannot preload join association `#{inspect atom}` with binding `#{var}` " <>
                   "because parent preload is not a join association"
  end

  defp assert_preload!(mode, _term) when mode in [:both, :preload], do: :ok
  defp assert_preload!(_mode, term) do
    Builder.error! "cannot preload `#{Macro.to_string(term)}` inside join association preload"
  end

  @doc """
  Applies the preloaded value into the query.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    binding = Builder.escape_binding(binding)
    {preloads, assocs} = escape(expr, binding)
    Builder.apply_query(query, __MODULE__, [Enum.reverse(preloads), Enum.reverse(assocs)], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term, term) :: Ecto.Query.t
  def apply(query, preloads, assocs) do
    query = Ecto.Queryable.to_query(query)
    %{query | preloads: query.preloads ++ preloads, assocs: query.assocs ++ assocs}
  end
end
