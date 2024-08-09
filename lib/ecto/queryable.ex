defprotocol Ecto.Queryable do
  @moduledoc """
  Converts a data structure into an `Ecto.Query`.

  This module defines a few default implementations so let us go over each and
  how to use them!

  ## Ecto.Query

  This is a simple pass through. If you are already using Ecto's query
  functions, this will simply return the already constructed `Ecto.Query`. Let's
  look at an example:

      User
      |> Ecto.Query.first()
      |> from()
      |> Repo.all()

  In this case, the `Ecto.Query.from/2` is actually unnecessary as it will
  simply return the query, in this case `Ecto.Query.first(User)`, unchanged.

  ## Ecto.SubQuery

  This implementation allows you to perform subqueries.

  ### Example

  This example is a bit contrived but imagine that you have a table of "people".
  Now imagine that you want to do something with people with the most common
  last names. To get that list, you could write something like:

      sub = from(
        p in Person,
        group_by: p.last_name,
        having: count(p.last_name) > 1,
        select: %{last_name: p.last_name, count: count(p.last_name)}
      )

  Now if you want to do something else with this data, perhaps join on
  additional tables and perform some calculations, you can do that as so:

      from(
        p in subquery(sub),
        # other filtering etc here
      )

  Please note that the `Ecto.Query.subquery/2` is needed here to convert the
  `Ecto.Query`
  into an instance of `Ecto.SubQuery`. This will ensure that the resulting
  query will use the provided subquery in the resulting FROM clause. Please see
  `Ecto.Query.subquery/2` for more information.

  ## BitString

  This implementation allows you to directly specify a table that you would like
  to query from:

      from(
        p in "people",
        select: {p.first_name, p.last_name}
      )

  While this is quite simple to use, it must be noted that `select/3` is
  required in this case. In the other implementations we have looked at so far,
  the query was always associated with an `Ecto.Schema` (`Person` above);
  however, when providing a `BitString`, Ecto uses this as a way to specify the
  underlying table to query, but does not try to infer any schema. This
  limitation now brings us to our next implementation!

  ## Tuple

  Similar to the `BitString` implementation, this allows you to specify the
  underlying table that you would like to query; however, this additionally
  allows you to specify the schema you would like to use:

      from(
        p in {"filtered_people", Person}
      )

  This can be particularly useful if you have database views that filter or
  aggregate the underlying data of a table but share the same schema. This means
  that you can reuse the same schema while specifying a separate "source" for
  the data.

  ## Atom

  This brings us to our final implementation which is also one of the most
  commonly used implementations. In fact, we have already seen this in use:

      from(
        p in Person
      )

  There it is! In case you did not know, Elixir modules are just atoms! This
  implementation takes the provided module name and then tries to load the
  associated schema. If no schema exists, it will raise
  `Protocol.UndefinedError`.
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
  def to_query(subquery) do
    %Ecto.Query{from: %Ecto.Query.FromExpr{source: subquery}}
  end
end

defimpl Ecto.Queryable, for: BitString do
  def to_query(source) when is_binary(source) do
    %Ecto.Query{from: %Ecto.Query.FromExpr{source: {source, nil}}}
  end
end

defimpl Ecto.Queryable, for: Atom do
  def to_query(module) do
    try do
      module.__schema__(:query)
    rescue
      UndefinedFunctionError ->
        message =
          if :code.is_loaded(module) do
            "the given module does not provide a schema"
          else
            "the given module does not exist"
          end

        raise Protocol.UndefinedError, protocol: @protocol, value: module, description: message

      FunctionClauseError ->
        raise Protocol.UndefinedError, protocol: @protocol, value: module, description: "the given module is an embedded schema"
    end
  end
end

defimpl Ecto.Queryable, for: Tuple do
  def to_query({source, schema} = from)
      when is_binary(source) and is_atom(schema) and not is_nil(schema) do
    %Ecto.Query{from: %Ecto.Query.FromExpr{source: from, prefix: schema.__schema__(:prefix)}}
  end
end
