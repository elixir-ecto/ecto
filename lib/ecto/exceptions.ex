alias Ecto.Query.Util

defexception Ecto.InvalidQuery, [:reason, :type, :query, :file, :line] do
  def message(Ecto.InvalidQuery[] = e) do
    if e.type && e.query && e.file && e.line do
      fl = Exception.format_file_line(e.file, e.line)
      "#{fl}: the query `#{e.type}: #{Macro.to_string(e.query)}` " <>
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

defexception Ecto.InvalidEntity, [:entity, :field, :type, :expected_type, :reason] do
  def message(Ecto.InvalidEntity[] = e) do
    expected_type = Util.type_to_ast(e.expected_type) |> Macro.to_string
    type = Util.type_to_ast(e.type) |> Macro.to_string
    "entity #{inspect e.entity} failed validation when #{e.reason}, " <>
    "field #{e.field} had type #{type} but type #{expected_type} was expected"
  end
end

defexception Ecto.NotSingleResult, [:entity, :primary_key, :id] do
  def message(Ecto.NotSingleResult[] = e) do
    "the result set from `#{e.entity}` where `#{e.primary_key} == #{e.id}` " <>
    "was not a single value"
  end
end

defexception Ecto.TypeCheckError, [:expr, :types, :allowed] do
  def message(Ecto.TypeCheckError[] = e) do
    { name, _, _ } = e.expr
    expected = Enum.map_join(e.allowed, "\n    ", &Macro.to_string(&1))

    types  = Enum.map(e.types, &Util.type_to_ast/1)
    actual = Macro.to_string({ name, [], types })

    """
    the following expression does not type check:

        #{Macro.to_string(e.expr)}

    Allowed types for #{name}/#{length(e.types)}:

        #{expected}

    Got: #{actual}
    """
  end
end

defexception Ecto.AssociationNotLoadedError, [:type, :name, :owner] do
  def message(Ecto.AssociationNotLoadedError[] = e) do
    "the #{e.type} association on #{e.owner}.#{e.name} was not loaded"
  end
end

defexception Ecto.MigrationDuplicationError, [:version] do
  def message(Ecto.MigrationDuplicationError[] = e) do
    """
    Current migration can't be executed.

    Versions are duplicated: #{e.version}
    """
  end
end

defexception Ecto.MigrationError, [:mod] do
  def message(Ecto.MigrationError[] = e) do
    """
    Module #{e.mod} must export __migration__/0 from Ecto.Migration.
    """
  end
end

defexception Ecto.MigrationPrivError, [:repo] do
  def message(Ecto.MigrationPrivError[] = e) do
    """
    A repository #{e.repo} needs to implement the priv/0 function.
    """
  end
end

defexception Ecto.MigrationCodeLoadError, [:err, :repo] do
  def message(Ecto.MigrationCodeLoadError[] = e) do
    """
    Migration module `#{e.repo}` loading error: #{e.err}
    """
  end
end