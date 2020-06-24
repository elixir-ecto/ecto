defmodule Ecto.Type.EmbedMany do
  alias Ecto.ParameterizedType

  use ParameterizedType

  # alias Ecto.Changeset

  defguardp equal_length_lists(a, b) when is_list(a) and is_list(b) and length(a) == length(b)

  @impl ParameterizedType
  def type(_opts), do: :list

  @valid_opts [:type, :required, :with, :on_replace, :field, :schema]
  @valid_on_replace [:delete, :raise, :mark_as_invalid]

  defp get_type(%{type: type}) when is_atom(type), do: type
  defp get_type(%{type: type}), do: raise "type must be an atom, got #{inspect type}"
  defp get_type(_), do: raise "type missing for embed"

  defp get_on_replace(%{on_replace: on_replace}) when on_replace in @valid_on_replace, do: on_replace
  defp get_on_replace(%{on_replace: on_replace, field: field}), do: raise ArgumentError, "Invalid on_replace for #{field}: #{inspect on_replace}"
  defp get_on_replace(_), do: :raise

  defp field(%{field: field}), do: field
  defp field(_), do: raise "Missing 'field' value for embed"

  defp schema(%{schema: schema}), do: schema
  defp schema(_), do: raise "Missing 'schema' value for embed"

  @impl ParameterizedType
  def init(opts) do
    opts = Enum.into(opts, %{})
    _type = get_type(opts)
    _on_replace = get_on_replace(opts)
    _field = field(opts)
    _schema = schema(opts)

    if (extra = Map.drop(opts, @valid_opts)) != %{}, do: raise "Invalid options specified: #{inspect extra}"

    opts
  end

  # def valid_with_function(_), do: true

  @impl ParameterizedType
  def cast(%{action: :ignore}, _current, _opts), do: :ignore

  def cast(data, current, opts), do: cast_or_change(data, current, opts, :cast)

  @impl ParameterizedType
  def load(data, opts) when is_list(data) do
    data
    |> Enum.map(&Ecto.Type.Embed.load(&1, opts))
    |> unzip()
  end

  def load(_, _), do: :error

  @impl ParameterizedType
  def dump(data, opts) when is_list(data) do
    data
    |> Enum.map(&Ecto.Type.Embed.dump(&1, opts))
    |> unzip()
  end

  def dump(_, _), do: :error

  @impl ParameterizedType
  def dump(value, dumper, %{field: field, type: schema}) do
    types = schema.__schema__(:dump)
    {:ok, Enum.map(value, &dump_embed(field, schema, &1, types, dumper))}
  end

  def dump(_, _, _) do
    :error
  end

  defp dump_embed(field, schema, %Ecto.Changeset{} = changeset, types, dumper) do
    dump_embed(field, schema, Ecto.Changeset.apply_changes(changeset), types, dumper)
  end

  defp dump_embed(_field, schema, %{__struct__: schema} = struct, types, dumper) do
    Ecto.Schema.Loader.safe_dump(struct, types, dumper)
  end

  defp dump_embed(field, schema, value, _types, _fun) do
    raise ArgumentError, "cannot dump embed `#{field}` of schema #{inspect schema}, invalid value: #{inspect value}"
  end

  def unzip(vals) do
    vals = Enum.reject(vals, & &1 == :ignore)

    if errors?(vals) do
      :error
    else
      {:ok, Enum.map(vals, &elem(&1, 1))}
    end
  end

  @impl ParameterizedType
  def equal?(a, b, opts) when equal_length_lists(a, b) do
    Enum.zip(a, b)
    |> Enum.all?(fn {x, y} -> Ecto.Type.Embed.equal?(x, y, opts) end)
  end

  def equal?(_, _, _), do: false

  @impl ParameterizedType
  def match?({:list, :any}, _opts), do: true
  def match?({:parameterized, __MODULE__, %{type: type}}, %{type: type}), do: true
  def match?(_, _), do: false

  @impl ParameterizedType
  def embed_as(_, _) do
    :dump
  end

  @impl ParameterizedType
  def apply_changes(changesets, opts) do
    for changeset <- changesets,
      struct = Ecto.Type.Embed.apply_changes(changeset, opts),
      do: struct
  end

  @impl ParameterizedType
  def missing?([], _opts), do: true
  def missing?(list, _opts) when is_list(list), do: false

  @impl ParameterizedType
  def change(data, current, opts), do: cast_or_change(data, current, opts, :change)

  defp errors?(items), do: :error in items

  defp all_ignore?(items), do: Enum.all?(items, & &1 == :ignore)

  @impl ParameterizedType
  def empty(_opts), do: []

  @impl ParameterizedType
  def validate_json_path!([path_field | rest], _field, opts) do
    unless is_integer(path_field) do
      raise "cannot use `#{path_field}` to refer to an item in `embeds_many`"
    end

    Ecto.Type.Embed.validate_json_path!(rest, path_field, opts)
  end

  def validate_json_path!([], _field, _opts) do
    :ok
  end

  defp cast_or_change(data, current, opts, :cast) when is_map(data) do
    data = data
      |> Enum.map(&key_as_int/1)
      |> Enum.sort
      |> Enum.map(&elem(&1, 1))

    cast_or_change(data, current, opts, :cast)
  end

  defp cast_or_change(data, nil, opts, cast_or_change), do: cast_or_change(data, [], opts, cast_or_change)
  # defp cast_or_change(nil, current, opts, cast_or_change), do: cast_or_change([], current, opts, cast_or_change)

  defp cast_or_change(data, current, opts, cast_or_change) when is_list(data) and is_list(current) do
    {to_update, to_add, to_delete} =  Enum.reduce(data, {[], [], current}, fn
      item, {to_update, to_add, to_delete} ->
        case find_item(item, to_delete) do
          {found, remaining} -> {[{item, found} | to_update], to_add, remaining}
          nil -> {to_update, [item | to_add], to_delete}
        end
      end)
    updates = Enum.map(to_update, fn {item, current} -> do_cast_or_change(cast_or_change, item, current, opts) end)
    adds = Enum.map(to_add, fn item -> do_cast_or_change(cast_or_change, item, nil, opts) end)
    deletes = Enum.map(to_delete, fn item -> do_cast_or_change(cast_or_change, nil, item, opts) end)

    changes = Enum.reverse(deletes) ++ Enum.reverse(updates) ++ Enum.reverse(adds)
    if errors?(changes) do
      cast_or_change_error(cast_or_change)
    else
      cast_or_change_return(cast_or_change, changes)
    end
  end

  defp cast_or_change(_, _, _, _), do: :error

  defp cast_or_change_error(:cast), do: :error
  defp cast_or_change_error(:change), do: {:error, {"is invalid", [type: {:array, :map}]}}

  defp cast_or_change_return(:cast, changes) do
    if all_ignore?(changes) do
      :ignore
    else
      {:ok, Enum.map(changes, &elem(&1, 1))}
    end
  end

  defp cast_or_change_return(:change, changes) do
    changes = Enum.reject(changes, & &1 == :ignore)
    changes = Enum.map(changes, &elem(&1, 1))
    invalid = Enum.any?(changes, & !&1.valid?)
    {:ok, changes, !invalid}
  end


  defp find_item(item, items) do
    case id(item) do
      nil -> nil
      id ->
        case Enum.split_with(items, & id(&1) == id) do
          {[], _} -> nil
          {[first | _], others} -> {first, others}
        end
    end
  end

  defp id(%Ecto.Changeset{} = changeset), do: "#{Ecto.Changeset.get_field(changeset, :id)}"
  defp id(%{"id" => id}), do: "#{id}"
  defp id(%{id: id}), do: "#{id}"
  defp id(_), do: nil

  defp do_cast_or_change(:cast, item, current, opts), do: Ecto.Type.Embed.cast(item, current, opts)
  defp do_cast_or_change(:change, item, current, opts), do: Ecto.Type.Embed.change(item, current, opts)

  defp key_as_int({key, val}) when is_binary(key) do
    case Integer.parse(key) do
      {key, ""} -> {key, val}
      _ -> {key, val}
    end
  end
  defp key_as_int(key_val), do: key_val
end
