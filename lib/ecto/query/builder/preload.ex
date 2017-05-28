import Kernel, except: [apply: 3]

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

      iex> escape([:foo, :bar], [])
      {[:foo, :bar], []}

      iex> escape([foo: [:bar, bar: :bat]], [])
      {[foo: [:bar, bar: [:bat]]], []}

      iex> escape([foo: {:^, [], ["external"]}], [])
      {[foo: "external"], []}

      iex> escape([foo: [:bar, {:^, [], ["external"]}], baz: :bat], [])
      {[foo: [:bar, "external"], baz: [:bat]], []}

      iex> escape([foo: {:c, [], nil}], [c: 1])
      {[], [foo: {1, []}]}

      iex> escape([foo: {{:c, [], nil}, bar: {:l, [], nil}}], [c: 1, l: 2])
      {[], [foo: {1, [bar: {2, []}]}]}

      iex> escape([foo: {:c, [], nil}, bar: {:l, [], nil}], [c: 1, l: 2])
      {[], [foo: {1, []}, bar: {2, []}]}

      iex> escape([foo: {{:c, [], nil}, :bar}], [c: 1])
      {[foo: [:bar]], [foo: {1, []}]}

      iex> escape([foo: [bar: {:c, [], nil}]], [c: 1])
      ** (Ecto.Query.CompileError) cannot preload join association `:bar` with binding `c` because parent preload is not a join association

  """
  @spec escape(Macro.t, Keyword.t) :: {[Macro.t], [Macro.t]} | no_return
  def escape(preloads, vars) do
    {preloads, assocs} = escape(preloads, :both, [], [], vars)
    {Enum.reverse(preloads), Enum.reverse(assocs)}
  end

  defp escape(atom, _mode, preloads, assocs, _vars) when is_atom(atom) do
    {[atom|preloads], assocs}
  end

  defp escape(list, mode, preloads, assocs, vars) when is_list(list) do
    Enum.reduce list, {preloads, assocs}, fn item, acc ->
      escape_each(item, mode, acc, vars)
    end
  end

  defp escape({:^, _, [inner]}, _mode, preloads, assocs, _vars) do
    {[inner|preloads], assocs}
  end

  defp escape(other, _mode, _preloads, _assocs, _vars) do
    Builder.error! "`#{Macro.to_string other}` is not a valid preload expression. " <>
                   "preload expects an atom, a list of atoms or a keyword list with " <>
                   "more preloads as values. Use ^ on the outermost preload to interpolate a value"
  end

  defp escape_each({key, {:^, _, [inner]}}, _mode, {preloads, assocs}, _vars) do
    key = escape_key(key)
    {[{key, inner}|preloads], assocs}
  end

  defp escape_each({key, {var, _, context}}, mode, {preloads, assocs}, vars) when is_atom(context) do
    assert_assoc!(mode, key, var)
    key = escape_key(key)
    idx = Builder.find_var!(var, vars)
    {preloads, [{key, {idx, []}}|assocs]}
  end

  defp escape_each({key, {{var, _, context}, list}}, mode, {preloads, assocs}, vars) when is_atom(context) do
    assert_assoc!(mode, key, var)
    key = escape_key(key)
    idx = Builder.find_var!(var, vars)
    {inner_preloads, inner_assocs} = escape(list, :assoc, [], [], vars)
    assocs = [{key, {idx, Enum.reverse(inner_assocs)}}|assocs]
    case inner_preloads do
      [] -> {preloads, assocs}
      _  -> {[{key, Enum.reverse(inner_preloads)}|preloads], assocs}
    end
  end

  defp escape_each({key, list}, _mode, {preloads, assocs}, vars) do
    key = escape_key(key)
    {inner_preloads, []} = escape(list, :preload, [], [], vars)
    {[{key, Enum.reverse(inner_preloads)}|preloads], assocs}
  end

  defp escape_each(other, mode, {preloads, assocs}, vars) do
    escape(other, mode, preloads, assocs, vars)
  end

  defp escape_key(atom) when is_atom(atom) do
    atom
  end

  defp escape_key({:^, _, [expr]}) do
    quote(do: Ecto.Query.Builder.Preload.key!(unquote(expr)))
  end

  defp escape_key(other) do
    Builder.error! "malformed key in preload `#{Macro.to_string(other)}` in query expression"
  end

  defp assert_assoc!(mode, _atom, _var) when mode in [:both, :assoc], do: :ok
  defp assert_assoc!(_mode, atom, var) do
    Builder.error! "cannot preload join association `#{Macro.to_string atom}` with binding `#{var}` " <>
                   "because parent preload is not a join association"
  end

  @doc """
  Called at runtime to check dynamic preload keys.
  """
  def key!(key) when is_atom(key),
    do: key
  def key!(key) do
    raise ArgumentError,
      "expected key in preload to be an atom, got: `#{inspect key}`"
  end

  @doc """
  Applies the preloaded value into the query.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding)
    {preloads, assocs} = escape(expr, binding)
    Builder.apply_query(query, __MODULE__, [Enum.reverse(preloads), Enum.reverse(assocs)], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term, term) :: Ecto.Query.t
  def apply(%Ecto.Query{preloads: p, assocs: a} = query, preloads, assocs) do
    %{query | preloads: p ++ preloads, assocs: a ++ assocs}
  end
  def apply(query, preloads, assocs) do
    apply(Ecto.Queryable.to_query(query), preloads, assocs)
  end
end
