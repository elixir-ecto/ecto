defexception Ecto.InvalidQuery, [:reason, :type, :query, :file, :line] do
  def message(Ecto.InvalidQuery[] = e) do
    if e.type && e.query && e.file && e.line do
      "the query #{e.type}: #{Macro.to_string(e.query)} at #{e.file}:#{e.line} " <>
      "is invalid: #{e.reason}"
    else
      e.reason
    end
  end
end

defexception Ecto.InvalidURL, [:url, :reason] do
  def message(Ecto.InvalidURL[url: url, reason: reason]) do
    "invalid url #{url}: #{reason}"
  end
end

defexception Ecto.NoPrimaryKey, [:entity, :reason] do
  def message(Ecto.NoPrimaryKey[entity: entity, reason: reason]) do
    "entity `#{elem(entity, 0)}` failed: #{reason} because it has no primary key"
  end
end

defexception Ecto.AdapterError, [:adapter, :reason, :internal] do
  def message(Ecto.AdapterError[adapter: adapter, reason: reason, internal: internal]) do
    "adapter #{inspect adapter} failed: #{reason}" <>
    if internal, do: "\ninternal error: #{inspect internal}", else: ""
  end
end

defexception Ecto.ValidationError, [:entity, :field, :type, :expected_type, :reason] do
  def message(Ecto.ValidationError[] = e) do
    "entity #{inspect e.entity} failed validation, field #{e.field} had " <>
    "type #{e.type} but type #{e.expected_type} was expected: #{e.reason}"
  end
end

defexception Ecto.NotSingleResult, [:entity, :primary_key, :id] do
  def message(Ecto.NotSingleResult[] = e) do
    "the result set from `#{e.entity}` where `#{e.primary_key} == #{e.id}` " <>
    "was too large"
  end
end

defexception Ecto.TypeCheckError, [:name, :expr, :types, :allowed] do
  def message(exception = Ecto.TypeCheckError[]) do
    expected = Enum.map_join(exception.allowed, "\n    ", &Macro.to_string(&1))

    types  = lc type inlist exception.types, do: { type, [], nil }
    actual = Macro.to_string({ exception.name, [], types })

    """
    the following expression does not type check:

        #{Macro.to_string(exception.expr)}

    Allowed types for #{exception.name}/#{length(exception.types)}:

        #{expected}

    Got: #{actual}
    """
  end
end
