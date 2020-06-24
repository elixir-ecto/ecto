defmodule Ecto.Type.Embed do
  alias Ecto.ParameterizedType

  use ParameterizedType

  alias Ecto.Changeset

  @impl ParameterizedType
  def type(_opts), do: :map

  @valid_opts [:type, :required, :with, :on_replace, :field, :schema]
  @valid_on_replace [:delete, :raise, :mark_as_invalid, :update]

  defp get_type(%{type: type}) when is_atom(type), do: type
  defp get_type(%{type: type}), do: raise "type must be an atom, got #{inspect type}"
  defp get_type(_), do: raise "type missing for embed"

  def get_with(%{with: wth}), do: wth
  def get_with(opts), do: fn a, b -> apply(get_type(opts), :changeset, [a, b]) end

  defp get_on_replace(%{on_replace: on_replace}) when on_replace in @valid_on_replace, do: on_replace
  defp get_on_replace(%{on_replace: on_replace, field: field}), do: raise ArgumentError, "Invalid on_replace for #{field}: #{inspect on_replace}"

  defp field(%{field: field}), do: field
  defp field(_), do: raise "Missing 'field' value for embed"

  defp schema(%{schema: schema}), do: schema
  defp schema(_), do: raise "Missing 'schema' value for embed"

  @impl ParameterizedType
  def init(opts) do
    opts = Enum.into(opts, %{})
    _type = get_type(opts)
    opts = Map.put_new(opts, :on_replace, :raise)
    _on_replace = get_on_replace(opts)
    _field = field(opts)
    _schema = schema(opts)

    if (extra = Map.drop(opts, @valid_opts)) != %{}, do: raise "Invalid options specified: #{inspect extra}"

    opts
  end

  # def valid_with_function(_), do: true

  @impl ParameterizedType
  def cast(%{action: :ignore}, _current, _opts), do: :ignore

  def cast(data, current, opts) when is_map(data) or is_nil(data) do
    {data, current}
    |> case do
      {nil, %_struct{}} -> :delete
      {%{}, nil} -> :insert
      _ ->
        case {id(data), id(current)} do
          {nil, nil} -> :replace
          {id, id} -> :update
          {_id, nil} -> :replace
          {_id1, _id2} ->  :replace
        end
    end
    |> case do
      :replace -> on_replace(opts)
      :delete ->
        case on_replace(opts) do
          :update -> :delete
          other -> other
        end
      other -> other
    end
    |> case do
      :delete ->
        {:ok, nil}

      :error ->
        :error

      action when action in [:update, :insert] ->
        current = current || struct(get_type(opts))
        case get_with(opts).(current, data) do
          %Changeset{valid?: true} = changeset -> {:ok, Map.put(changeset, :action, action)}
          %Changeset{} = changeset -> {:error, Map.put(changeset, :action, action)}
        end
    end
  end

  def cast(_, _, _), do: :error

  defp on_replace(%{on_replace: :raise} = opts) do
    raise """
    you are attempting to change relation #{inspect field(opts)} of
    #{inspect schema(opts)} but the `:on_replace` option of
    this relation is set to `:raise`.

    By default it is not possible to replace or delete embeds and
    associations during `cast`. Therefore Ecto requires all existing
    data to be given on update. Failing to do so results in this
    error message.

    If you want to replace data or automatically delete any data
    not sent to `cast`, please set the appropriate `:on_replace`
    option when defining the relation. The docs for `Ecto.Changeset`
    covers the supported options in the "Associations, embeds and on
    replace" section.

    However, if you don't want to allow data to be replaced or
    deleted, only updated, make sure that:

      * If you are attempting to update an existing entry, you
        are including the entry primary key (ID) in the data.

      * If you have a relationship with many children, at least
        the same N children must be given on update.

    """
  end

  defp on_replace(%{on_replace: :mark_as_invalid}), do: :error

  defp on_replace(%{on_replace: :delete}), do: :delete

  defp on_replace(%{on_replace: :update}), do: :update

  defp id(%{id: id}), do: id
  defp id(%{"id" => id}), do: id
  defp id(_), do: nil

  @impl ParameterizedType
  def load(%{} = data, opts) do
    {:ok, struct(get_type(opts), data)}
  end

  def load(_, _), do: :error

  @impl ParameterizedType
  def dump(%Changeset{valid?: false}, _opts), do: :error

  def dump(%Changeset{} = changeset, opts) do
    dump(Changeset.apply_changes(changeset), opts)
  end

  def dump(%type{} = struct, opts) do
    if type == get_type(opts) do
      {:ok, Map.from_struct(struct)}
    else
      :error
    end
  end

  def dump(_, _), do: :error

  @impl ParameterizedType
  def dump(value, dumper, %{field: field, type: schema}) do
    {:ok, dump_embed(field, schema, value, schema.__schema__(:dump), dumper)}
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

  defp dump_embed(field, _schema, value, _types, _fun) do
    raise ArgumentError, "cannot dump embed `#{field}`, invalid value: #{inspect value}"
  end

  @impl ParameterizedType
  def equal?(a, %Changeset{} = b, _opts) do
    a == Changeset.apply_changes(b)
  end

  def equal?(a, b, _opts) do
    a == b
  end

  @impl ParameterizedType
  def match?({:map, :any}, _opts), do: true
  def match?({:parameterized, __MODULE__, %{type: type}}, %{type: type}), do: true
  def match?(_, _), do: false


  @impl ParameterizedType
  def embed_as(_, _) do
    :dump
  end

  @impl ParameterizedType
  def apply_changes(nil, _opts), do: nil
  def apply_changes(%Changeset{action: :delete}, _opts),  do: nil
  def apply_changes(%Changeset{action: :replace}, _opts), do: nil
  def apply_changes(%Changeset{} = changeset, _opts), do: Changeset.apply_changes(changeset)

  def change(%{action: :ignore}, _, _), do: :ignore

  def change(nil, nil, _opts), do: {:ok, nil, true}

  def change(nil, current, opts) do
    case current && on_replace(opts) do
      :error -> :error
      _ -> {:ok, nil, true}
    end
  end

  @impl ParameterizedType
  def change(%type1{} = value, current, %{type: type2} = opts) when type1 == type2 or type1 == Ecto.Changeset do
    {action, current} = if current == nil do
      {:insert, struct!(get_type(opts), %{})}
    else
      {:update, current}
    end

    action = case value do
      %{action: nil} -> action
      %{action: action} -> action
      _ -> action
    end

    value = case value do
      %Changeset{changes: changes} -> changes
      %_{} -> value |> Map.from_struct() |> Map.drop([:__meta__]) |> Map.to_list()
      %{} -> value |> Map.drop([:__meta__]) |> Map.to_list()
    end

    if action == :update && on_replace(opts) == :error do
        :error
    else
        changeset = current
        |> Changeset.change(value)
        |> assert_changeset_struct!(opts)
        |> put_new_action(action)

        if changeset.changes == %{} && has_primary_key(opts) do
          :ignore
        else
          {:ok, changeset, changeset.valid?}
        end
    end
  end

  # Struct other than the embedded type
  def change(%_{}, _current, _) do
    :error
  end

  def change(%{} = value, current, %{type: type} = opts) do
    change(struct!(type, value), current, opts)
  end

  def change(value, current, %{type: type} = opts) when is_list(value) do
    if Keyword.keyword?(value) do
      change(struct!(type, value), current, opts)
    else
      :error
    end
  end

  def change(_, _, _), do: :error

  defp assert_changeset_struct!(%{data: %{__struct__: mod}} = changeset, %{type: mod}) do
    changeset
  end

  defp assert_changeset_struct!(%{data: data}, %{type: mod}) do
    raise ArgumentError, "expected changeset data to be a #{mod} struct, got: #{inspect data}"
  end

  defp put_new_action(%{action: action} = changeset, new_action) when is_nil(action),
    do: Map.put(changeset, :action, new_action)

  defp put_new_action(changeset, _new_action),
    do: changeset

  @impl ParameterizedType
  def validate_json_path!([path_field | rest], field, %{type: type}) do
    unless path_field in Enum.map(type.__schema__(:fields), &Atom.to_string/1) do
      raise "field `#{path_field}` does not exist in #{inspect(type)}"
    end

    path_type = type.__schema__(:type, String.to_atom(path_field))

    case path_type do
      {:parameterized, Ecto.Type.Embed, opts} -> Ecto.Type.Embed.validate_json_path!(rest, path_field, opts)
      {:parameterized, Ecto.Type.EmbedMany, opts} -> Ecto.Type.EmbedMany.validate_json_path!(rest, path_field, opts)
      other ->
        if rest == [] do
          :ok
        else
          raise "Unexpected path type found in embed for field #{inspect field}: #{inspect other}"
        end
    end
  end

  def validate_json_path!([], _field, _opts) do
    :ok
  end

  def has_primary_key(%{type: type}), do: type.__schema__(:primary_key) != []
end
