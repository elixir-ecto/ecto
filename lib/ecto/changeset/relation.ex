defmodule Ecto.Changeset.Relation do
  @moduledoc false

  alias Ecto.Changeset
  alias Ecto.Association.NotLoaded

  @type t :: %{cardinality: :one | :many,
               on_replace: :raise | :mark_as_invalid | atom,
               relationship: :parent | :child,
               ordered: boolean,
               owner: atom,
               related: atom,
               field: atom}

  @doc """
  Builds the related data.
  """
  @callback build(t) :: Ecto.Schema.t

  @doc """
  Returns empty container for relation.
  """
  def empty(%{cardinality: cardinality}), do: cardinality_to_empty(cardinality)

  defp cardinality_to_empty(:one), do: nil
  defp cardinality_to_empty(:many), do: []

  @doc """
  Checks if the container can be considered empty.
  """
  def empty?(%{cardinality: _}, %NotLoaded{}), do: true
  def empty?(%{cardinality: :many}, []), do: true
  def empty?(%{cardinality: :many}, changes), do: filter_empty(changes) == []
  def empty?(%{cardinality: :one}, nil), do: true
  def empty?(%{}, _), do: false

  @doc """
  Filter empty changes
  """
  def filter_empty(changes) do
    Enum.filter(changes, fn
      %Changeset{action: action} when action in [:replace, :delete] -> false
      _ -> true
    end)
  end

  @doc """
  Applies related changeset changes
  """
  def apply_changes(%{cardinality: :one}, nil) do
    nil
  end

  def apply_changes(%{cardinality: :one}, changeset) do
    apply_changes(changeset)
  end

  def apply_changes(%{cardinality: :many}, changesets) do
    for changeset <- changesets,
      struct = apply_changes(changeset),
      do: struct
  end

  defp apply_changes(%Changeset{action: :delete}),  do: nil
  defp apply_changes(%Changeset{action: :replace}), do: nil
  defp apply_changes(changeset), do: Changeset.apply_changes(changeset)

  @doc """
  Loads the relation with the given struct.

  Loading will fail if the association is not loaded but the struct is.
  """
  def load!(%{__meta__: %{state: :built}}, %NotLoaded{__cardinality__: cardinality}) do
    cardinality_to_empty(cardinality)
  end

  def load!(struct, %NotLoaded{__field__: field}) do
    raise "attempting to cast or change association `#{field}` " <>
          "from `#{inspect struct.__struct__}` that was not loaded. Please preload your " <>
          "associations before manipulating them through changesets"
  end

  def load!(_struct, loaded), do: loaded

  @doc """
  Casts related according to the `on_cast` function.
  """
  def cast(%{cardinality: :one} = relation, nil, current, _on_cast) do
    case current && on_replace(relation, current) do
      :error -> {:error, {"is invalid", [type: expected_type(relation)]}}
      _ -> {:ok, nil, true}
    end
  end

  def cast(%{cardinality: :many} = relation, params, current, on_cast) when is_map(params) do
    params =
      params
      |> Enum.map(&key_as_int/1)
      |> Enum.sort
      |> Enum.map(&elem(&1, 1))
    cast(relation, params, current, on_cast)
  end

  def cast(%{related: mod} = relation, params, current, on_cast) do
    pks = mod.__schema__(:primary_key)
    with :error <- cast_or_change(relation, params, current, data_pk(pks),
                                  param_pk(mod, pks), &do_cast(relation, &1, &2, &3, on_cast)) do
      {:error, {"is invalid", [type: expected_type(relation)]}}
    end
  end

  defp do_cast(meta, params, struct, allowed_actions, {module, fun, args})
       when is_atom(module) and is_atom(fun) and is_list(args) do
    on_cast = fn changeset, attrs ->
      apply(module, fun, [changeset, attrs | args])
    end

    do_cast(meta, params, struct, allowed_actions, on_cast)
  end

  defp do_cast(meta, params, nil, allowed_actions, on_cast) do
    {:ok,
      on_cast.(meta.__struct__.build(meta), params)
      |> put_new_action(:insert)
      |> check_action!(allowed_actions)}
  end

  defp do_cast(relation, nil, current, _allowed_actions, _on_cast) do
    on_replace(relation, current)
  end

  defp do_cast(_meta, params, struct, allowed_actions, on_cast) do
    {:ok,
      on_cast.(struct, params)
      |> put_new_action(:update)
      |> check_action!(allowed_actions)}
  end

  @doc """
  Wraps related structs in changesets.
  """
  def change(%{cardinality: :one} = relation, nil, current) do
    case current && on_replace(relation, current) do
      :error -> {:error, {"is invalid", [type: expected_type(relation)]}}
      _ -> {:ok, nil, true}
    end
  end

  def change(%{related: mod} = relation, value, current) do
    get_pks = data_pk(mod.__schema__(:primary_key))
    with :error <- cast_or_change(relation, value, current, get_pks, get_pks,
                                  &do_change(relation, &1, &2, &3)) do
      {:error, {"is invalid", [type: expected_type(relation)]}}
    end
  end

  # This may be an insert or an update, get all fields.
  defp do_change(relation, %{__struct__: _} = changeset_or_struct, nil, _allowed_actions) do
    changeset = Changeset.change(changeset_or_struct)
    {:ok,
     changeset
     |> assert_changeset_struct!(relation)
     |> put_new_action(action_from_changeset(changeset))}
  end

  defp do_change(relation, nil, current, _allowed_actions) do
    on_replace(relation, current)
  end

  defp do_change(relation, %Changeset{} = changeset, _current, allowed_actions) do
    {:ok,
     changeset
     |> assert_changeset_struct!(relation)
     |> put_new_action(:update)
     |> check_action!(allowed_actions)}
  end

  defp do_change(_relation, %{__struct__: _} = struct, _current, allowed_actions) do
    {:ok, struct |> Ecto.Changeset.change |> put_new_action(:update) |> check_action!(allowed_actions)}
  end

  defp do_change(%{related: mod} = relation, changes, current, allowed_actions)
      when is_list(changes) or is_map(changes) do
    changeset = Ecto.Changeset.change(current || mod.__struct__, changes)
    changeset = put_new_action(changeset, action_from_changeset(changeset))
    do_change(relation, changeset, current, allowed_actions)
  end

  defp action_from_changeset(%{data: %{__meta__: %{state: state}}}) do
    case state do
      :built   -> :insert
      :loaded  -> :update
      :deleted -> :delete
    end
  end
  defp action_from_changeset(_) do
    :insert # We don't care if it is insert/update for embeds (no meta)
  end

  defp assert_changeset_struct!(%{data: %{__struct__: mod}} = changeset, %{related: mod}) do
    changeset
  end
  defp assert_changeset_struct!(%{data: data}, %{related: mod}) do
    raise ArgumentError, "expected changeset data to be a #{mod} struct, got: #{inspect data}"
  end

  @doc """
  Handles the changeset or struct when being replaced.
  """
  def on_replace(%{on_replace: :mark_as_invalid}, _changeset_or_struct) do
    :error
  end

  def on_replace(%{on_replace: :raise, field: name, owner: owner}, _) do
    raise """
    you are attempting to change relation #{inspect name} of
    #{inspect owner} but the `:on_replace` option of
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

  def on_replace(_relation, changeset_or_struct) do
    {:ok, Changeset.change(changeset_or_struct) |> put_new_action(:replace)}
  end

  defp raise_if_updating_with_struct!(%{field: name, owner: owner}, %{__struct__: _} = new) do
    raise """
    you have set that the relation #{inspect name} of #{inspect owner}
    has `:on_replace` set to `:update` but you are giving it a struct/
    changeset to put_assoc/put_change.

    Since you have set `:on_replace` to `:update`, you are only allowed
    to update the existing entry by giving updated fields as a map or
    keyword list or set it to nil.

    If you indeed want to replace the existing #{inspect name}, you have
    to change the foreign key field directly.

    Got: #{inspect new}
    """
  end

  defp raise_if_updating_with_struct!(_, _) do
    true
  end

  defp cast_or_change(%{cardinality: :one} = relation, value, current, current_pks_fun, new_pks_fun, fun)
       when is_map(value) or is_list(value) or is_nil(value) do
    single_change(relation, value, current_pks_fun, new_pks_fun, fun, current)
  end

  defp cast_or_change(%{cardinality: :many}, [], [], _current_pks, _new_pks, _fun) do
    {:ok, [], true}
  end

  defp cast_or_change(%{cardinality: :many} = relation, value, current, current_pks_fun, new_pks_fun, fun)
       when is_list(value) do
    {current_pks, current_map} = process_current(current, current_pks_fun)
    %{unique: unique, ordered: ordered} = relation
    ordered = if ordered, do: current_pks, else: []
    map_changes(value, new_pks_fun, fun, current_map, [], true, true, unique && %{}, ordered)
  end

  defp cast_or_change(_, _, _, _, _, _), do: :error

  # single change

  defp single_change(_relation, nil, _current_pks_fun, _new_pks_fun, fun, current) do
    single_change(nil, current, fun, [:update, :delete], false)
  end

  defp single_change(_relation, new, _current_pks_fun, _new_pks_fun, fun, nil) do
    single_change(new, nil, fun, [:insert], false)
  end

  defp single_change(%{on_replace: on_replace} = relation, new, current_pks_fun, new_pks_fun, fun, current) do
    pk_values = new_pks_fun.(new)

    if (pk_values == current_pks_fun.(current) and pk_values != []) or
         (on_replace == :update and raise_if_updating_with_struct!(relation, new)) do
      single_change(new, current, fun, allowed_actions(pk_values), true)
    else
      case on_replace(relation, current) do
        {:ok, _changeset} -> single_change(new, nil, fun, [:insert], false)
        :error -> :error
      end
    end
  end

  defp single_change(new, current, fun, allowed_actions, skippable?) do
    case fun.(new, current, allowed_actions) do
      {:ok, %{action: :ignore}} ->
        :ignore
      {:ok, changeset} ->
        if skippable? and skip?(changeset) do
          :ignore
        else
          {:ok, changeset, changeset.valid?}
        end
      :error ->
        :error
    end
  end

  # map changes

  defp map_changes([changes | rest], new_pks, fun, current, acc, valid?, skip?, unique, ordered)
      when is_map(changes) or is_list(changes) do
    pk_values = new_pks.(changes)
    {struct, current, allowed_actions} = pop_current(current, pk_values)

    case fun.(changes, struct, allowed_actions) do
      {:ok, %{action: :ignore}} ->
        ordered = pop_ordered(pk_values, ordered)
        map_changes(rest, new_pks, fun, current, acc, valid?, skip?, unique, ordered)
      {:ok, changeset} ->
        changeset = maybe_add_error_on_pk(changeset, pk_values, unique)
        acc = [changeset | acc]
        valid? = valid? and changeset.valid?
        skip? = (struct != nil) and skip? and skip?(changeset)
        unique = unique && Map.put(unique, pk_values, true)
        ordered = pop_ordered(pk_values, ordered)
        map_changes(rest, new_pks, fun, current, acc, valid?, skip?, unique, ordered)
      :error ->
        :error
    end
  end

  defp map_changes([], _new_pks, fun, current, acc, valid?, skip?, _unique, ordered) do
    current_structs = Enum.map(current, &elem(&1, 1))
    skip? = skip? and ordered == []
    reduce_delete_changesets(current_structs, fun, Enum.reverse(acc), valid?, skip?)
  end

  defp map_changes(_params, _new_pks, _fun, _current, _acc, _valid?, _skip?, _unique, _ordered) do
    :error
  end

  defp pop_ordered(pk_values, [pk_values | tail]), do: tail
  defp pop_ordered(_pk_values, tail), do: tail

  defp maybe_add_error_on_pk(%{data: %{__struct__: schema}} = changeset, pk_values, unique) do
    if is_map(unique) and not missing_pks?(pk_values) and Map.has_key?(unique, pk_values) do
      Enum.reduce(schema.__schema__(:primary_key), changeset, fn pk, acc ->
        Changeset.add_error(acc, pk, "has already been taken")
      end)
    else
      changeset
    end
  end

  defp missing_pks?(pk_values) do
    pk_values == [] or Enum.any?(pk_values, &is_nil/1)
  end

  defp allowed_actions(pk_values) do
    if Enum.all?(pk_values, &is_nil/1) do
      [:insert, :update, :delete]
    else
      [:update, :delete]
    end
  end

  defp reduce_delete_changesets([struct | rest], fun, acc, valid?, _skip?) do
    case fun.(nil, struct, [:update, :delete]) do
      {:ok, changeset} ->
        valid? = valid? and changeset.valid?
        reduce_delete_changesets(rest, fun, [changeset | acc], valid?, false)

      :error ->
        :error
    end
  end

  defp reduce_delete_changesets([], _fun, _acc, _valid?, true), do: :ignore
  defp reduce_delete_changesets([], _fun, acc, valid?, false), do: {:ok, acc, valid?}

  # helpers

  defp check_action!(changeset, allowed_actions) do
    action = changeset.action

    cond do
      action in allowed_actions ->
        changeset
      action == :ignore ->
        changeset
      action == :insert ->
        raise "cannot #{action} related #{inspect changeset.data} " <>
              "because it is already associated with the given struct"
      true ->
        raise "cannot #{action} related #{inspect changeset.data} because " <>
              "it already exists and it is not currently associated with the " <>
              "given struct. Ecto forbids casting existing records through " <>
              "the association field for security reasons. Instead, set " <>
              "the foreign key value accordingly"
    end
  end

  defp key_as_int({key, val}) when is_binary(key) do
    case Integer.parse(key) do
      {key, ""} -> {key, val}
      _ -> {key, val}
    end
  end
  defp key_as_int(key_val), do: key_val

  defp process_current(nil, _get_pks),
    do: {[], %{}}
  defp process_current(current, get_pks) do
    Enum.map_reduce(current, %{}, fn struct, acc ->
      pks = get_pks.(struct)
      key = if pks == [], do: map_size(acc), else: pks
      {pks, Map.put(acc, key, struct)}
    end)
  end

  defp pop_current(current, pk_values) do
    case Map.pop(current, pk_values) do
      {nil, current} -> {nil, current, [:insert]}
      {struct, current} -> {struct, current, allowed_actions(pk_values)}
    end
  end

  defp data_pk(pks) do
    fn
      %Changeset{data: data} -> Enum.map(pks, &Map.get(data, &1))
      map when is_map(map) -> Enum.map(pks, &Map.get(map, &1))
      list when is_list(list) -> Enum.map(pks, &Keyword.get(list, &1))
    end
  end

  defp param_pk(mod, pks) do
    pks = Enum.map(pks, &{&1, Atom.to_string(&1), mod.__schema__(:type, &1)})
    fn params ->
      Enum.map pks, fn {atom_key, string_key, type} ->
        original = Map.get(params, string_key) || Map.get(params, atom_key)
        case Ecto.Type.cast(type, original) do
          {:ok, value} -> value
          _ -> original
        end
      end
    end
  end

  defp put_new_action(%{action: action} = changeset, new_action) when is_nil(action),
    do: Map.put(changeset, :action, new_action)
  defp put_new_action(changeset, _new_action),
    do: changeset

  defp skip?(%{valid?: true, changes: empty, action: :update}) when empty == %{},
    do: true
  defp skip?(_changeset),
    do: false

  defp expected_type(%{cardinality: :one}), do: :map
  defp expected_type(%{cardinality: :many}), do: {:array, :map}
end
