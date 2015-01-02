defprotocol Ecto.Queryable do
  @moduledoc """
  Converts a data structure into an `Ecto.Query` struct.

  The only function required to implement is `to_query` which does the conversion.
  """

  def to_query(expr)
end

defimpl Ecto.Queryable, for: Ecto.Query do
  def to_query(query), do: query
end

defimpl Ecto.Queryable, for: BitString do
  def to_query(source) when is_binary(source),
    do: %Ecto.Query{from: {source, nil}}
end

defimpl Ecto.Queryable, for: Atom do
  def to_query(module) do
    try do
      %Ecto.Query{from: {module.__schema__(:source), module}}
    rescue
      UndefinedFunctionError ->
        message = if Code.ensure_loaded?(module) do
          "the given module is not queryable"
        else
          "the given module does not exist"
        end

        raise Protocol.UndefinedError,
             protocol: @protocol,
                value: module,
          description: message
    end
  end
end
