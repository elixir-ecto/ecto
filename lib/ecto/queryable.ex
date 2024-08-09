defprotocol Ecto.Queryable do
  @moduledoc """
  Converts a data structure into an `Ecto.Query`.

  This is used by `Ecto.Repo` and also `from` macro. For example, `Repo.all`
  expects any queryable as argument, which is why you can do `Repo.all(MySchema)`
  or `Repo.all(query)`. Furthermore, when you write `from ALIAS in QUERYABLE`,
  `QUERYABLE` accepts any data structure that implements `Ecto.Queryable`.

  This module defines a few default implementations so let us go over each and
  how to use them.

  ## Atom

  The most common use case for this protocol is to convert atoms representing
  an `Ecto.Schema` module into a query. This is what happens when you write:

      query = from(p in Person)

  Or when you directly pass a schema to a repository:

      Repo.all(Person)

  In case you did not know, Elixir modules are just atoms. This implementation
  takes the provided module name and then tries to load the associated schema.
  If no schema exists, it will raise `Protocol.UndefinedError`.

  ## BitString

  This implementation allows you to directly specify a table that you would like
  to query from:

      from(
        p in "people",
        select: {p.first_name, p.last_name}
      )

  Or:

      Repo.delete_all("people")

  While this is quite simple to use, some repository operations, such as
  `Repo.all`, require a `select` clause. When you query a schema, the
  select is automatically defined for you based on the schema fields,
  but when you pass a table directly, you need to explicitly list them.
  This limitation now brings us to our next implementation!

  ## Tuple

  Similar to the `BitString` implementation, this allows you to specify the
  underlying table that you would like to query; however, this additionally
  allows you to specify the schema you would like to use:

      from(p in {"filtered_people", Person})

  This can be particularly useful if you have database views that filter or
  aggregate the underlying data of a table but share the same schema. This means
  that you can reuse the same schema while specifying a separate "source" for
  the data.

  ## Ecto.Query

  This is a simple pass through. After all, all `Ecto.Query` instances
  can be converted into `Ecto.Query`:

      Repo.all(from u in User, where: u.active)

  This also enables Ecto queries to compose, since we can pass one query
  as the source of another:

      active_users = from u in User, where: u.active
      ordered_active_users = from u in active_users, order_by: u.created_at

  ## Ecto.SubQuery

  Ecto also allows you to compose queries using subqueries.  Imagine you
  have a table of "people". Now imagine that you want to do something with
  people with the most common last names. To get that list, you could write
  something like:

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
  `Ecto.Query` into an instance of `Ecto.SubQuery`. This protocol then wraps
  it into an `Ecto.Query`, but using the provided subquery in the FROM clause.
  Please see `Ecto.Query.subquery/2` for more information.
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
