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

defimpl Ecto.Queryable, for: Ecto.SubQuery do
  def to_query(subquery), do: %Ecto.Query{from: subquery}
end

defimpl Ecto.Queryable, for: BitString do
  def to_query(source) when is_binary(source),
    do: %Ecto.Query{from: %Ecto.Query.FromExpr{source: source, schema: nil}}
end

defimpl Ecto.Queryable, for: Atom do
  def to_query(module) do
    try do
      module.__schema__(:query)
    rescue
      UndefinedFunctionError ->
        message = if :code.is_loaded(module) do
          "the given module does not provide a schema"
        else
          "the given module does not exist"
        end

        raise Protocol.UndefinedError,
          protocol: @protocol, value: module, description: message
    end
  end
end

defimpl Ecto.Queryable, for: Tuple do
  def to_query({source, %Ecto.Query{from: {_, schema}} = query}) when is_binary(source),
    do: %{query | from: %Ecto.Query.FromExpr{source: source, schema: schema}}

  def to_query({source, %Ecto.Query{from: %Ecto.Query.FromExpr{schema: schema}} = query}) when is_binary(source),
    do: %{query | from: %Ecto.Query.FromExpr{source: source, schema: schema}}

  def to_query({source, schema}) when is_binary(source) and is_atom(schema) and not is_nil(schema),
    do: %Ecto.Query{from: %Ecto.Query.FromExpr{source: source, schema: schema}, prefix: schema.__schema__(:prefix)}
end

defimpl Ecto.Queryable, for: Ecto.Query.FromExpr do
  def to_query(%Ecto.Query.FromExpr{schema: schema} = from) when is_atom(schema),
    do: %Ecto.Query{from: from, prefix: schema.__schema__(:prefix)}

  def to_query(%Ecto.Query.FromExpr{} = from),
    do: %Ecto.Query{from: from}
end
