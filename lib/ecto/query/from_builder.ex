defmodule Ecto.Query.FromBuilder do
  @moduledoc false

  # For now we keep our bound var from (from x in X) as { var, entity }
  # even though it can just be entity, since we are order dependent,
  # not name dependent.
  # Revisit this when we introduce the new syntax
  def escape({ :in, _, [{ var, _, context}, {:__aliases__, _, _} = entity] } = ast, env)
      when is_atom(var) and is_atom(context) do

    entity = Macro.expand(entity, env)
    valid = is_atom(entity) and
      Code.ensure_compiled?(entity) and
      function_exported?(entity, :__ecto__, 1)

    unless valid do
      reason = "`#{Module.to_binary(entity)}` is not an Ecto entity"
      raise Ecto.InvalidQuery, reason: reason, type: :from, query: ast, file: env.file, line: env.line
    end

    { var, entity }
  end

  def escape(other, env) do
    reason = "only `in` expressions binding variables to entities are allowed"
    raise Ecto.InvalidQuery, reason: reason, type: :from, query: other, file: env.file, line: env.line
  end
end
