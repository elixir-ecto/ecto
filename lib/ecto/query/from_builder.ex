defmodule Ecto.Query.FromBuilder do
  @moduledoc false

  def escape({ :in, _, [{ var, _, context}, {:__aliases__, _, _} = entity] }, env)
      when is_atom(var) and is_atom(context) do

    entity = Macro.expand(entity, env)
    valid = is_atom(entity) and
      Code.ensure_compiled?(entity) and
      function_exported?(entity, :__ecto__, 1)

    unless valid do
      message = "`#{Module.to_binary(entity)}` is not an Ecto entity"
      raise Ecto.InvalidQuery, message: message
    end

    { var, entity }
  end

  def escape(_other, _env) do
    message = "only `in` expressions binding variables to records allowed in from expressions"
    raise Ecto.InvalidQuery, message: message
  end
end
