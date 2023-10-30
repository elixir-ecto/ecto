defmodule Ecto.Query.FilterModel do
  @moduledoc """
  Allows a user to take any module that implements Ecto.Schema and
  build a query using a map that represents that schema's data shape.
  This works for parameterized and associated types in a schema as well.

  ## Example

      defmodule Foo do
        use Ecto.Schema

        schema "foo" do
          field :numeric, :integer

          # Bar has a field "year"
          has_many :bar, Bar
        end
      end

      Foo
      |> FilterModel.derive(%{
        # where c.numeric >= 10 and c.numeric <= 20
        numeric: %{
          gte: 10,
          lte: 20
        },
        # where([c], c.id in subquery(from b in Bar, where: b.year == 2018))
        bar: %{
          year: 2018
        }
      })
      # The final query appears similar to:
      # from f in Foo, where: c.id in subquery(
      #   from b in Bar, select: %{id: b.foo_id}, where: b.year == 2018
      # ) and c.numeric >= 10 and c.numeric <= 20
      |> Repo.all()

    ## Model Values

    Model values can be one of the following:

    - A list of values passed into an `in` statement: i.e. `foo: [1, 2, 3]` will
    translate to `where([s], s.foo in ^[1, 2, 3])`
    - A map configuring comparisons or query functions. `gte`, `lte`, and `ilike`
    are presently supported. I.e. `bar: %{ilike: "%Some Text%"}` becomes
    `where([s], ilike(s.bar, "%Some Text%"))
    - `nil` -- i.e. `baz: nil` becomes `where([s], is_nil(s.baz))`
    - `:any` -- i.e. `bing: :any` becomes `where([s], not is_nil(s.bing))`
  """

  import Ecto.Query

  def derive(schema, models) when is_list(models) do
    models
    |> Enum.map(&derive(schema, &1))
    |> Enum.reduce(fn
      query, acc ->
        acc
        |> union(^query)
    end)
  end

  def derive(schema, model) do
    {field_models, association_models} = validate_fields(schema, model)

    schema
    |> maybe_build_initial_query()
    |> filter_associations(association_models)
    |> filter_values(field_models)
  end

  defp validate_fields(%Ecto.Query{from: %{source: {_table, schema}}}, model),
    do: validate_fields(schema, model)

  defp validate_fields(schema, model) do
    model = atomize_keys(model)
    valid_keys = validate_and_split_keys(schema)
    parameterized_fields = derive_parameterized_fields(schema)

    valid_field_info =
      valid_keys
      |> Map.get(:field_keys, [])
      |> derive_valid_field_info(parameterized_fields)

    valid_field_keys = Map.keys(valid_field_info)

    valid_association_info =
      valid_keys
      |> Map.get(:association_keys, [])
      |> derive_valid_association_info(schema)

    valid_association_keys = Map.keys(valid_association_info)

    field_models =
      model
      |> Map.take(valid_field_keys)
      |> Enum.map(&{elem(&1, 0), elem(&1, 1), Map.get(valid_field_info, elem(&1, 0))})

    association_models =
      model
      |> Map.take(valid_association_keys)
      |> Enum.map(&{elem(&1, 0), elem(&1, 1), Map.get(valid_association_info, elem(&1, 0))})

    {field_models, association_models}
  end

  defp maybe_build_initial_query(%Ecto.Query{} = query), do: query
  defp maybe_build_initial_query(schema), do: from(s in schema)

  defp atomize_keys(model) do
    model
    |> Enum.map(fn
      {key, val} when is_binary(key) -> {String.to_existing_atom(key), val}
      {key, val} -> {key, val}
    end)
    |> Map.new()
  end

  defp validate_and_split_keys(schema) do
    schema
    |> struct()
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Enum.group_by(
      fn
        {_key, %Ecto.Association.NotLoaded{}} ->
          :association_keys

        {_key, _} ->
          :field_keys
      end,
      fn {key, _} -> key end
    )
  end

  defp derive_parameterized_fields(schema) do
    schema.__changeset__
    |> Stream.map(fn
      {key, {:parameterized, Ecto.Enum, %{mappings: mappings}}} ->
        {key, Map.new(mappings)}

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp derive_valid_field_info(keys, parameterized_fields) do
    keys
    |> Enum.map(
      &{
        &1,
        %{
          mappings: Map.get(parameterized_fields, &1, %{})
        }
      }
    )
    |> Map.new()
  end

  defp derive_valid_association_info(keys, schema) do
    keys
    |> Enum.map(
      &{
        &1,
        :association
        |> schema.__schema__(&1)
        |> Map.take([:queryable, :related_key])
      }
    )
    |> Map.new()
  end

  defp filter_associations(query, association_models),
    do: Enum.reduce(association_models, query, &derive_filters_from_associations/2)

  defp derive_filters_from_associations(
         {_key, model, %{queryable: queryable, related_key: related_key}},
         query
       ) do
    assoc_subquery =
      from(aq in queryable, select: %{id: field(aq, ^related_key)})
      |> derive(model)

    query
    |> join(:inner, [q], sq in subquery(assoc_subquery), on: sq.id == q.id)
  end

  defp derive_filters_from_associations(_, query),
    do: query

  defp filter_values(query, field_models),
    do: Enum.reduce(field_models, query, &derive_filter_from_values/2)

  defp derive_filter_from_values({attr, values, %{mappings: mappings}}, query)
       when is_list(values) do
    mapped_values = apply_mappings(values, mappings)
    where(query, [q], field(q, ^attr) in ^mapped_values)
  end

  defp derive_filter_from_values({attr, values, %{mappings: mappings}}, query)
       when is_map(values),
       do:
         Enum.reduce(values, query, fn filter_value, query ->
           apply_map_value(attr, mappings, filter_value, query)
         end)

  defp derive_filter_from_values({attr, value, _}, query) when is_nil(value),
    do: where(query, [q], is_nil(field(q, ^attr)))

  defp derive_filter_from_values({attr, :any, _}, query),
    do: where(query, [q], not is_nil(field(q, ^attr)))

  defp derive_filter_from_values({attr, value, %{mappings: mappings}}, query)
       when is_boolean(value) or is_integer(value) or is_atom(value) or is_binary(value) do
    mapped_value = apply_mappings(value, mappings)
    where(query, [q], field(q, ^attr) == ^mapped_value)
  end

  defp derive_filter_from_values(_, query), do: query

  defp apply_map_value(attr, mappings, filter_value, query)

  defp apply_map_value(attr, mappings, {opt, val}, acc) when is_binary(opt),
    do: apply_map_value(attr, mappings, {String.to_existing_atom(opt), val}, acc)

  defp apply_map_value(attr, mappings, {:gte, val}, acc) do
    mapped_val = apply_mappings(val, mappings)
    where(acc, [q], field(q, ^attr) >= ^mapped_val)
  end

  defp apply_map_value(attr, mappings, {:lte, val}, acc) do
    mapped_val = apply_mappings(val, mappings)
    where(acc, [q], field(q, ^attr) <= ^mapped_val)
  end

  defp apply_map_value(attr, _mappings, {:ilike, val}, acc) do
    where(acc, [q], ilike(field(q, ^attr), ^val))
  end

  defp apply_map_value(_attr, _mappings, _, acc), do: acc

  defp apply_mappings(values, mappings) when is_list(values) do
    values |> Enum.map(&apply_mappings(&1, mappings))
  end

  defp apply_mappings(value, mappings), do: Map.get(mappings, value, value)
end
