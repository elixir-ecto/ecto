defprotocol Ecto.Queryable do
  @moduledoc """
  Converts a data structure into an `Ecto.Query`.
  """

  @doc """
  Converts the given `data` into an `Ecto.Query`.
  """
  def to_query(data)
end

defimpl Ecto.Queryable, for: Ecto.Query do
  def to_query(query), do: query
end

defimpl Ecto.Queryable, for: BitString do
  def to_query(source) when is_binary(source),
    do: %Ecto.Query{from: {source, source, nil}}
end

defimpl Ecto.Queryable, for: Atom do
  def to_query(module) do
    try do
      source = module.__schema__(:source)
      %Ecto.Query{from: {source, source, module}}
    rescue
      UndefinedFunctionError ->
        message = if :code.is_loaded(module) do
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

defimpl Ecto.Queryable, for: Tuple do
  def to_query(from = {search_path, source, model})
    when is_binary(search_path) and is_binary(source) and is_atom(model),
    do: %Ecto.Query{from: from}
end
