defmodule Ecto.Changeset.Relation do
  @moduledoc false

  alias Ecto.Changeset
  alias Ecto.Association.NotLoaded

  @type t :: %{cardinality: :one | :many,
               on_replace: :raise | :mark_as_invalid | atom,
               relationship: :parent | :child,
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
  def empty(%{cardinality: cardinality}), do: do_empty(cardinality)

  defp do_empty(:one), do: nil
  defp do_empty(:many), do: []

  @doc """
  Checks if the container can be considered empty.
  """
  def empty?(%{cardinality: _}, %NotLoaded{}), do: true
  def empty?(%{cardinality: :many}, []), do: true
  def empty?(%{cardinality: :one}, nil), do: true
  def empty?(%{}, _), do: false

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
    do_empty(cardinality)
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
      :error -> :error
      _ -> {:ok, nil, true, false}
    end
  end

  def cast(%{cardinality: :many} = relation, params, current, on_cast) when is_map(params) do
    params =
      params
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))
    cast(relation, params, current, on_cast)
  end

  def cast(%{related: mod} = relation, params, current, on_cast) do
    pks = primary_keys!(mod)
    cast_or_change(relation, params, current, struct_pk(mod, pks),
                   param_pk(mod, pks), &do_cast(relation, &1, &2, &3, on_cast))
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
      :error -> :error
      _ -> {:ok, nil, true, false}
    end
  end

  def change(%{related: mod} = relation, value, current) do
    get_pks = struct_pk(mod, primary_keys!(mod))
    cast_or_change(relation, value, current, get_pks, get_pks,
                   &do_change(relation, &1, &2, &3))
  end

  # This may be an insert or an update, get all fields.
  defp do_change(_relation, %{__struct__: _} = changeset_or_struct, nil, _allowed_actions) do
    changeset = Changeset.change(changeset_or_struct)
    {:ok, put_new_action(changeset, action_from_changeset(changeset))}
  end

  defp do_change(relation, nil, current, _allowed_actions) do
    on_replace(relation, current)
  end

  defp do_change(_relation, %Changeset{} = changeset, _current, allowed_actions) do
    {:ok, put_new_action(changeset, :update) |> check_action!(allowed_actions)}
  end

  defp do_change(%{field: field}, %{__struct__: _}, _current, _allowed_actions) do
    raise """
    cannot change `#{field}` with a struct because one is
    already embedded/associated.

    To solve this issue, you must explicitly transform such
    structs into changesets, so Ecto can properly track how
    and when each embed/association is changing.

    For example, instead of

        Ecto.Changeset.put_assoc(changeset, :children, children_structs)

    do

        children_changesets = Enum.map(children_structs, &Ecto.Changeset.change/1)
        Ecto.Changeset.put_assoc(changeset, :children, children_changesets)

    By giving changesets, Ecto knows exactly how to track changes
    keeping your database operations efficient and safe.
    """
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

  @doc """
  Handles the changeset or struct when being replaced.
  """
  def on_replace(%{on_replace: :mark_as_invalid}, _changeset_or_struct) do
    :error
  end

  def on_replace(%{on_replace: :raise, field: name, owner: owner}, _) do
    raise """
    you are attempting to change relation #{inspect name} of
    #{inspect owner}, but there is missing data.

    If you are attempting to update an existing entry, please make sure
    you include the entry primary key (ID) alongside the data.

    If you have a relationship with many children, at least the same N
    children must be given on update. By default it is not possible to
    orphan embed nor associated records, attempting to do so results in
    this error message.

    It is possible to change this behaviour by setting `:on_replace` when
    defining the relation. See `Ecto.Changeset`'s section on related data
    for more info.
    """
  end

  def on_replace(_relation, changeset_or_struct) do
    {:ok, Changeset.change(changeset_or_struct) |> put_new_action(:replace)}
  end

  defp cast_or_change(%{cardinality: :one} = relation, value, current, current_pks,
                      new_pks, fun) when is_map(value) or is_list(value) or is_nil(value) do
    single_change(relation, value, current_pks, new_pks, fun, current)
  end

  defp cast_or_change(%{cardinality: :many}, [], [], _current_pks, _new_pks, _fun) do
    {:ok, [], true, false}
  end

  defp cast_or_change(%{cardinality: :many}, value, current, current_pks,
                      new_pks, fun) when is_list(value) do
    map_changes(value, current_pks, new_pks, fun, current)
  end

  defp cast_or_change(_, _, _, _, _, _), do: :error

  # single change

  defp single_change(_relation, nil, _current_pks, _new_pks, fun, current) do
    single_change(nil, current, fun, [:update, :delete], false)
  end

  defp single_change(_relation, new, _current_pks, _new_pks, fun, nil) do
    single_change(new, nil, fun, [:insert], false)
  end

  defp single_change(relation, new, current_pks, new_pks, fun, current) do
    if new_pks.(new) == current_pks.(current) do
      single_change(new, current, fun, [:update, :delete], true)
    else
      case on_replace(relation, current) do
        {:ok, _} -> single_change(new, nil, fun, [:insert], false)
        :error   -> :error
      end
    end
  end

  defp single_change(new, current, fun, allowed_actions, skippable?) do
    case fun.(new, current, allowed_actions) do
      {:ok, changeset} ->
        {:ok, changeset, changeset.valid?, skippable? and skip?(changeset)}
      :error ->
        :error
    end
  end

  # map changes

  defp map_changes(list, current_pks, new_pks, fun, current) do
    map_changes(list, new_pks, fun, process_current(current, current_pks), [], true, true)
  end

  defp map_changes([], _pks, fun, current, acc, valid?, skip?) do
    current_structs = Enum.map(current, &elem(&1, 1))
    reduce_delete_changesets(current_structs, fun, Enum.reverse(acc), valid?, skip?)
  end

  defp map_changes([changes | rest], new_pks, fun, current, acc, valid?, skip?)
      when is_map(changes) or is_list(changes) do
    pk_values = new_pks.(changes)

    {struct, current, allowed_actions} =
      case Map.fetch(current, pk_values) do
        {:ok, struct} ->
          {struct, Map.delete(current, pk_values), [:update, :delete]}
        :error ->
          {nil, current, [:insert]}
      end

    case fun.(changes, struct, allowed_actions) do
      {:ok, changeset} ->
        map_changes(rest, new_pks, fun, current, [changeset | acc],
                    valid? and changeset.valid?, (struct != nil) and skip? and skip?(changeset))
      :error ->
        :error
    end
  end

  defp map_changes(_params, _pks, _fun, _current, _acc, _valid?, _skip?) do
    :error
  end

  defp reduce_delete_changesets([], _fun, acc, valid?, skip?) do
    {:ok, acc, valid?, skip?}
  end

  defp reduce_delete_changesets([struct | rest], fun, acc, valid?, _skip?) do
    case fun.(nil, struct, [:update, :delete]) do
      {:ok, changeset} ->
        reduce_delete_changesets(rest, fun, [changeset | acc],
                                 valid? and changeset.valid?, false)
      :error ->
        :error
    end
  end

  # helpers

  defp check_action!(changeset, allowed_actions) do
    action = changeset.action

    cond do
      action in allowed_actions ->
        changeset
      action == :insert ->
        raise "cannot #{action} related #{inspect changeset.data} " <>
              "because it is already associated to the given struct"
      true ->
        raise "cannot #{action} related #{inspect changeset.data} because " <>
              "it already exists and it is not currently associated to the " <>
              "given struct. Ecto forbids casting existing records through " <>
              "the association field for security reasons. Instead, set " <>
              "the foreign key value accordingly"
    end
  end

  defp process_current(nil, _get_pks),
    do: %{}
  defp process_current(current, get_pks) do
    Enum.reduce(current, %{}, fn struct, acc ->
      Map.put(acc, get_pks.(struct), struct)
    end)
  end

  defp struct_pk(_mod, pks) do
    fn
      %Changeset{data: struct} -> Enum.map(pks, &Map.get(struct, &1))
      [_|_] = struct -> Enum.map(pks, &Keyword.get(struct, &1))
      %{} = struct -> Enum.map(pks, &Map.get(struct, &1))
    end
  end

  defp param_pk(mod, pks) do
    pks = Enum.map(pks, &{&1, Atom.to_string(&1), mod.__schema__(:type, &1)})
    fn params ->
      Enum.map pks, fn {atom_key, string_key, type} ->
        original = Map.get(params, string_key) || Map.get(params, atom_key)
        case Ecto.Type.cast(type, original) do
          {:ok, value} -> value
          :error       -> original
        end
      end
    end
  end

  defp primary_keys!(schema) do
    case schema.__schema__(:primary_key) do
      []  -> raise Ecto.NoPrimaryKeyFieldError, schema: schema
      pks -> pks
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
end
