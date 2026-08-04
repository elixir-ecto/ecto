import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Select do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes a select.

  It allows tuples, lists and variables at the top level. Inside the
  tuples and lists query expressions are allowed.

  ## Examples

      iex> escape({1, 2}, [], __ENV__)
      {{:{}, [], [:{}, [], [1, 2]]}, {[], %{take: %{}, subqueries: [], aliases: %{}}}}

      iex> escape([1, 2], [], __ENV__)
      {[1, 2], {[], %{take: %{}, subqueries: [], aliases: %{}}}}

      iex> escape(quote(do: x), [x: 0], __ENV__)
      {{:{}, [], [:&, [], [0]]}, {[], %{take: %{}, subqueries: [], aliases: %{}}}}

  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: {Macro.t, {list, %{take: map, subqueries: list}}}
  def escape(atom, _vars, _env)
      when is_atom(atom) and not is_boolean(atom) and atom != nil do
    Builder.error! """
    #{inspect(atom)} is not a valid query expression, :select expects a query expression or a list of fields
    """
  end

  def escape(other, vars, env) do
    cond do
      take?(other) ->
        {
          {:{}, [], [:&, [], [0]]},
          {[], %{take: %{0 => {:any, Macro.expand(other, env)}}, subqueries: [], aliases: %{}}}
        }

      maybe_take?(other) ->
        Builder.error! """
        Cannot mix fields with interpolations, such as: `select: [:foo, ^:bar, :baz]`. \
        Instead interpolate all fields at once, such as: `select: ^[:foo, :bar, :baz]`. \
        Got: #{Macro.to_string(other)}.
        """

      true ->
        {expr, {params, acc}} = escape(other, {[], %{take: %{}, subqueries: [], aliases: %{}}}, vars, env)
        acc = %{acc | subqueries: Enum.reverse(acc.subqueries)}
        {expr, {params, acc}}
    end
  end

  # Tuple
  defp escape({left, right}, params_acc, vars, env) do
    escape({:{}, [], [left, right]}, params_acc, vars, env)
  end

  # Tuple
  defp escape({:{}, _, list}, params_acc, vars, env) do
    {list, params_acc} = Enum.map_reduce(list, params_acc, &escape(&1, &2, vars, env))
    expr = {:{}, [], [:{}, [], list]}
    {expr, params_acc}
  end

  # Struct
  defp escape({:%, _, [name, map]}, params_acc, vars, env) do
    name = Macro.expand(name, env)
    {escaped_map, params_acc} = escape(map, params_acc, vars, env)
    {{:{}, [], [:%, [], [name, escaped_map]]}, params_acc}
  end

  # Map
  defp escape({:%{}, _, [{:|, _, [data, pairs]}]}, params_acc, vars, env) do
    {escaped_data, params_acc} = escape(data, params_acc, vars, env)
    {pairs, params_acc} = escape_pairs(pairs, data, params_acc, vars, env)
    {{:{}, [], [:%{}, [], [{:{}, [], [:|, [], [escaped_data, pairs]]}]]}, params_acc}
  end

  # Merge
  defp escape({:merge, _, [left, {kind, _, _} = right]}, params_acc, vars, env)
       when kind in [:%{}, :map] do
    {left, params_acc} = escape(left, params_acc, vars, env)
    {right, params_acc} = escape(right, params_acc, vars, env)
    {{:{}, [], [:merge, [], [left, right]]}, params_acc}
  end

  defp escape({:merge, _, [_left, right]}, _params_acc, _vars, _env) do
    Builder.error! "expected the second argument of merge/2 in select to be a map, got: `#{Macro.to_string(right)}`"
  end

  # Map
  defp escape({:%{}, _, pairs}, params_acc, vars, env) do
    {pairs, params_acc} = escape_pairs(pairs, nil, params_acc, vars, env)
    {{:{}, [], [:%{}, [], pairs]}, params_acc}
  end

  # List
  defp escape(list, params_acc, vars, env) when is_list(list) do
    Enum.map_reduce(list, params_acc, &escape(&1, &2, vars, env))
  end

  # map/struct(var, [:foo, :bar])
  defp escape({tag, _, [{var, _, context}, fields]}, {params, acc}, vars, env)
       when tag in [:map, :struct] and is_atom(var) and is_atom(context) do
    taken = escape_fields(fields, tag, env)
    expr = Builder.escape_var!(var, vars)
    acc = add_take(acc, Builder.find_var!(var, vars), {tag, taken})
    {expr, {params, acc}}
  end

  # aliased values
  defp escape({:selected_as, _, [expr, name]}, {params, acc}, vars, env) do
    name = Builder.quoted_atom!(name, "selected_as/2")
    {escaped, {params, acc}} = Builder.escape(expr, :any, {params, acc}, vars, env)
    expr = {:{}, [], [:selected_as, [], [escaped, name]]}
    aliases = Builder.add_select_alias(acc.aliases, name)
    {expr, {params, %{acc | aliases: aliases}}}
  end

  defp escape(expr, params_acc, vars, env) do
    Builder.escape(expr, :any, params_acc, vars, {env, &escape_expansion/5})
  end

  defp escape_expansion(expr, _type, params_acc, vars, env) do
    escape(expr, params_acc, vars, env)
  end

  defp escape_pairs(pairs, update_data, params_acc, vars, env) do
    Enum.map_reduce(pairs, params_acc, fn {k, v}, acc ->
      v = tag_update_param(update_data, k, v)
      {k, acc} = escape_key(k, acc, vars, env)
      {v, acc} = escape(v, acc, vars, env)
      {{k, v}, acc}
    end)
  end

  defp tag_update_param({var, _, context}, field, {:^, _,[_]} = param) when is_atom(var) and is_atom(context) do
    {:type, [], [param, {{:., [], [{var, [], context}, field]}, [], []}]}
  end

  defp tag_update_param(_, _, value), do: value

  defp escape_key(k, params_acc, _vars, _env) when is_atom(k) do
    {k, params_acc}
  end

  defp escape_key({:^, _, [k]}, params_acc, _vars, _env) do
    checked = quote do: Ecto.Query.Builder.Select.map_key!(unquote(k))
    {checked, params_acc}
  end

  defp escape_key(k, params_acc, vars, env) do
    escape(k, params_acc, vars, env)
  end

  defp escape_fields({:^, _, [interpolated]}, tag, _env) do
    quote do
      Ecto.Query.Builder.Select.fields!(unquote(tag), unquote(interpolated))
    end
  end
  defp escape_fields(expr, tag, env) do
    case Macro.expand(expr, env) do
      fields when is_list(fields) ->
        fields
      _ ->
        Builder.error!(
          "`#{tag}/2` in `select` expects either a literal or " <>
            "an interpolated (1) list of atom fields, (2) dynamic, or " <>
            "(3) map with dynamic values"
        )
    end
  end

  @doc """
  Called at runtime to verify a field.
  """
  def fields!(tag, fields) do
    if take?(fields) do
      fields
    else
      raise ArgumentError,
        "expected a list of fields in `#{tag}/2` inside `select`, got: `#{inspect fields}`"
    end
  end

  @doc """
  Called at runtime to verify a map key
  """
  def map_key!(key) when is_binary(key), do: key
  def map_key!(key) when is_integer(key), do: key
  def map_key!(key) when is_float(key), do: key
  def map_key!(key) when is_atom(key), do: key

  def map_key!(other) do
    Builder.error!(
      "interpolated map keys in `:select` can only be atoms, strings or numbers, got: #{inspect(other)}"
    )
  end

  # atom list sigils
  defp take?({name, _, [_, modifiers]}) when name in ~w(sigil_w sigil_W)a do
    ?a in modifiers
  end

  defp take?(fields) do
    is_list(fields) and Enum.all?(fields, fn
      {k, v} when is_atom(k) -> take?(List.wrap(v))
      k when is_atom(k) -> true
      _ -> false
    end)
  end

  defp maybe_take?(fields) do
    is_list(fields) and Enum.any?(fields, fn
      {k, v} when is_atom(k) -> maybe_take?(List.wrap(v))
      k when is_atom(k) -> true
      _ -> false
    end)
  end

  @doc """
  Called at runtime for interpolated/dynamic selects.
  """
  def select!(kind, query, fields, file, line) when is_map(fields) do
    {expr, {params, subqueries, aliases, _count}} = expand_nested(fields, {[], [], %{}, 0}, query)

    %Ecto.Query.SelectExpr{
      expr: expr,
      params: Enum.reverse(params),
      subqueries: Enum.reverse(subqueries),
      aliases: aliases,
      file: file,
      line: line
    }
    |> apply_or_merge(kind, query)
  end

  def select!(kind, query, fields, file, line) do
    take = %{0 => {:any, fields!(:select, fields)}}

    %Ecto.Query.SelectExpr{expr: {:&, [], [0]}, take: take, file: file, line: line}
    |> apply_or_merge(kind, query)
  end

  defp apply_or_merge(select, kind, query) do
    if kind == :select do
      apply(query, select)
    else
      merge(query, select)
    end
  end

  defp expand_nested(%Ecto.Query.DynamicExpr{} = dynamic, {params, subqueries, aliases, count}, query) do
    {expr, params, subqueries, aliases, count} =
      Ecto.Query.Builder.Dynamic.partially_expand(query, dynamic, params, subqueries, aliases, count)

    {expr, {params, subqueries, aliases, count}}
  end

  defp expand_nested(%Ecto.SubQuery{} = subquery, {params, subqueries, aliases, count}, _query) do
    index = length(subqueries)
    # used both in ast and in parameters, as a placeholder.
    expr = {:subquery, index}
    params = [expr | params]
    subqueries = [subquery | subqueries]
    count = count + 1

    {expr, {params, subqueries, aliases, count}}
  end

  defp expand_nested(%type{} = fields, acc, query) do
    {fields, acc} = fields |> Map.from_struct() |> expand_nested(acc, query)
    {{:%, [], [type, fields]}, acc}
  end

  defp expand_nested(fields, acc, query) when is_map(fields) do
    {fields, acc} = fields |> Enum.map_reduce(acc, &expand_nested_pair(&1, &2, query))
    {{:%{}, [], fields}, acc}
  end

  defp expand_nested(invalid, _acc, query) when is_list(invalid) or is_tuple(invalid) do
    raise Ecto.QueryError,
      query: query,
      message:
        "Interpolated map values in :select can only be " <>
          "maps, structs, dynamics, subqueries and literals. Got #{inspect(invalid)}"
  end

  defp expand_nested(other, acc, _query) do
    {other, acc}
  end

  defp expand_nested_pair({key, val}, acc, query) do
    {val, acc} = expand_nested(val, acc, query)
    {{key, val}, acc}
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(:select | :merge, Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t

  def build(kind, query, _binding, {:^, _, [var]}, env) do
    quote do
      Ecto.Query.Builder.Select.select!(unquote(kind), unquote(query), unquote(var),
                                        unquote(env.file), unquote(env.line))
    end
  end

  def build(kind, query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding, env)
    {expr, {params, acc}} = escape(expr, binding, env)
    params = Builder.escape_params(params)
    take = {:%{}, [], Map.to_list(acc.take)}
    aliases = escape_aliases(acc.aliases)

    select = quote do: %Ecto.Query.SelectExpr{
                         expr: unquote(expr),
                         params: unquote(params),
                         file: unquote(env.file),
                         line: unquote(env.line),
                         take: unquote(take),
                         subqueries: unquote(acc.subqueries),
                         aliases: unquote(aliases)}

    if kind == :select do
      Builder.apply_query(query, __MODULE__, [select], env)
    else
      quote do
        query = unquote(query)
        Builder.Select.merge(query, unquote(select))
      end
    end
  end

  defp escape_aliases(%{} = aliases), do: {:%{}, [], Map.to_list(aliases)}
  defp escape_aliases(aliases), do: aliases

  @doc """
  The callback applied by `build/5` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(%Ecto.Query{select: nil} = query, expr) do
    %{query | select: expr}
  end
  def apply(%Ecto.Query{}, _expr) do
    Builder.error! "only one select expression is allowed in query"
  end
  def apply(query, expr) do
    apply(Ecto.Queryable.to_query(query), expr)
  end

  @doc """
  The callback applied by `build/5` when merging.
  """
  def merge(%Ecto.Query{select: nil} = query, new_select) do
    merge(query, new_select, {:&, [], [0]}, [], [], %{}, %{}, new_select)
  end
  def merge(%Ecto.Query{select: old_select} = query, new_select) do
    %{expr: old_expr, params: old_params, subqueries: old_subqueries, take: old_take, aliases: old_aliases} = old_select
    merge(query, old_select, old_expr, old_params, old_subqueries, old_take, old_aliases, new_select)
  end
  def merge(query, expr) do
    merge(Ecto.Queryable.to_query(query), expr)
  end

  defp merge(query, select, old_expr, old_params, old_subqueries, old_take, old_aliases, new_select) do
    %{expr: new_expr, params: new_params, subqueries: new_subqueries, take: new_take, aliases: new_aliases} = new_select

    new_expr =
      new_expr
      |> Ecto.Query.Builder.bump_interpolations(old_params)
      |> Ecto.Query.Builder.bump_subqueries(old_subqueries)

    expr =
      case {classify_merge(old_expr, old_take), classify_merge(new_expr, new_take)} do
        {_, _} when old_expr == new_expr ->
          new_expr

        {{:source, meta, ix}, {:source, _, ix}} ->
          {:&, meta, [ix]}

        {{:struct, meta, name, old_fields}, {:map, _, new_fields}} when old_params == [] ->
          cond do
            new_fields == [] ->
              old_expr

            Keyword.keyword?(old_fields) and Keyword.keyword?(new_fields) ->
              {:%, meta, [name, {:%{}, meta, Keyword.merge(old_fields, new_fields)}]}

            true ->
              {:merge, [], [old_expr, new_expr]}
          end

        {{:map, meta, old_fields}, {:map, _, new_fields}} ->
          cond do
            old_fields == [] ->
              new_expr

            new_fields == [] ->
              old_expr

            true ->
              require_distinct_keys? = old_params != []

              case merge_map_fields(old_fields, new_fields, require_distinct_keys?) do
                fields when is_list(fields) ->
                  {:%{}, meta, fields}

                :error ->
                  {:merge, [], [old_expr, new_expr]}
              end
          end

        {_, {:map, _, _}} ->
          {:merge, [], [old_expr, new_expr]}

        {_, _} ->
          message = """
          cannot select_merge #{merge_argument_to_error(new_expr, query)} into \
          #{merge_argument_to_error(old_expr, query)}, those select expressions \
          are incompatible. You can only select_merge:

            * a source (such as post) with another source (of the same type)
            * a source (such as post) with a map
            * a struct with a map
            * a map with a map

          Incompatible merge found
          """

          raise Ecto.QueryError, query: query, message: message
      end

    select = %{
      select | expr: expr,
               params: old_params ++ bump_subquery_params(new_params, old_subqueries),
               subqueries: old_subqueries ++ new_subqueries,
               take: merge_take(query, old_expr, old_take, new_take),
               aliases: merge_aliases(old_aliases, new_aliases)
    }

    %{query | select: select}
  end

  defp classify_merge({:&, meta, [ix]}, take) when is_integer(ix) do
    case take do
      %{^ix => {:map, _}} -> {:map, meta, :runtime}
      _ -> {:source, meta, ix}
    end
  end

  defp classify_merge({:%, meta, [name, {:%{}, _, fields}]}, _take)
       when fields == [] or tuple_size(hd(fields)) == 2 do
    {:struct, meta, name, fields}
  end

  defp classify_merge({:%{}, meta, fields}, _take)
       when fields == [] or tuple_size(hd(fields)) == 2 do
    {:map, meta, fields}
  end

  defp classify_merge({:%{}, meta, _}, _take) do
    {:map, meta, :runtime}
  end

  defp classify_merge(_, _take) do
    :error
  end

  defp merge_map_fields(old_fields, new_fields, false) do
    if Keyword.keyword?(old_fields) and Keyword.keyword?(new_fields) do
      Keyword.merge(old_fields, new_fields)
    else
      :error
    end
  end

  defp merge_map_fields(old_fields, new_fields, true) when is_list(old_fields) do
    if Keyword.keyword?(new_fields) do
      valid? =
        Enum.reduce_while(old_fields, true, fn
          {k, _v}, _ when is_atom(k) ->
            if Keyword.has_key?(new_fields, k),
              do: {:halt, false},
              else: {:cont, true}

          _, _ ->
            {:halt, false}
        end)

      if valid?, do: old_fields ++ new_fields, else: :error
    else
      :error
    end
  end

  defp merge_map_fields(_, _, true), do: :error

  defp merge_argument_to_error({:&, _, [0]}, %{from: %{source: {source, alias}}}) do
    "source #{inspect(source || alias)}"
  end

  defp merge_argument_to_error({:&, _, [ix]}, _query) do
    "join (at position #{ix})"
  end

  defp merge_argument_to_error(other, _query) do
    Macro.to_string(other)
  end

  defp add_take(acc, key, value) do
    take = Map.update(acc.take, key, value, &merge_take_kind_and_fields(key, &1, value))
    %{acc | take: take}
  end

  defp bump_subquery_params(new_params, old_subqueries) do
    len = length(old_subqueries)

    Enum.map(new_params, fn
      {:subquery, counter} -> {:subquery, len + counter}
      other -> other
    end)
  end

  defp merge_take(query, old_expr, %{} = old_take, %{} = new_take) do
    Enum.reduce(new_take, old_take, fn {binding, {new_kind, new_fields} = new_value}, acc ->
      case acc do
        %{^binding => old_value} ->
          Map.put(acc, binding, merge_take_kind_and_fields(binding, old_value, new_value))

        %{} ->
          # If merging with a schema, add the schema's query fields. This comes in handy if the user
          # is merging fields with load_in_query = false.
          # If merging with a schemaless source, do nothing so the planner can take all the fields.
          case old_expr do
            {:&, _, [^binding]} ->
              source = Enum.at([query.from | query.joins], binding).source

              case source do
                {_, schema} when schema != nil ->
                  Map.put(acc, binding, {new_kind, Enum.uniq(new_fields ++ schema.__schema__(:query_fields))})

                _ ->
                  acc
              end

            _ ->
              Map.put(acc, binding, new_value)
          end
      end
    end)
  end

  defp merge_take_kind_and_fields(binding, {old_kind, old_fields}, {new_kind, new_fields}) do
    {merge_take_kind(binding, old_kind, new_kind), Enum.uniq(old_fields ++ new_fields)}
  end

  defp merge_take_kind(_, kind, kind), do: kind
  defp merge_take_kind(_, :any, kind), do: kind
  defp merge_take_kind(_, kind, :any), do: kind
  defp merge_take_kind(binding, old, new) do
    Builder.error! "cannot select_merge because the binding at position #{binding} " <>
                   "was previously specified as a `#{old}` and later as `#{new}`"
  end

  defp merge_aliases(old_aliases, new_aliases) do
    Enum.reduce(new_aliases, old_aliases, fn {alias, _}, aliases ->
      Builder.add_select_alias(aliases, alias)
    end)
  end
end
