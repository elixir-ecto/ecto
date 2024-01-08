defmodule Ecto.Changeset.Relation do
  @moduledoc false

  require Logger
  alias Ecto.Changeset
  alias Ecto.Association.NotLoaded

  @type t :: %{required(:__struct__) => atom(),
               required(:cardinality) => :one | :many,
               required(:on_replace) => :raise | :mark_as_invalid | atom,
               required(:relationship) => :parent | :child,
               required(:ordered) => boolean,
               required(:owner) => atom,
               required(:related) => atom,
               required(:field) => atom,
               optional(atom()) => any()}

  @doc """
  Builds the related data.
  """
  @callback build(t, owner :: Ecto.Schema.t) :: Ecto.Schema.t

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
  def cast(%{cardinality: :one} = relation, _owner, nil, current, _on_cast) do
    case current && on_replace(relation, current) do
      :error -> {:error, {"is invalid", [type: expected_type(relation)]}}
      _ -> {:ok, nil, true}
    end
  end

  def cast(%{cardinality: :one} = relation, owner, params, current, on_cast) when is_list(params) do
    if Keyword.keyword?(params) do
      cast(relation, owner, Map.new(params), current, on_cast)
    else
      {:error, {"is invalid", [type: expected_type(relation)]}}
    end
  end

  def cast(%{related: mod} = relation, owner, params, current, on_cast) do
    pks = mod.__schema__(:primary_key)
    fun = &do_cast(relation, owner, &1, &2, &3, &4, on_cast)
    data_pk = data_pk(pks)
    param_pk = param_pk(mod, pks)

    with :error <- cast_or_change(relation, params, current, data_pk, param_pk, fun) do
      {:error, {"is invalid", [type: expected_type(relation)]}}
    end
  end

  defp do_cast(meta, owner, params, struct, allowed_actions, idx, {module, fun, args})
       when is_atom(module) and is_atom(fun) and is_list(args) do
    IO.warn "passing a MFA to :with in cast_assoc/cast_embed is deprecated, please pass an anonymous function instead"

    on_cast = fn changeset, attrs ->
      apply(module, fun, [changeset, attrs | args])
    end

    do_cast(meta, owner, params, struct, allowed_actions, idx, on_cast)
  end

  defp do_cast(relation, owner, params, nil = _struct, allowed_actions, idx, on_cast) do
    {:ok,
      relation
      |> apply_on_cast(on_cast, relation.__struct__.build(relation, owner), params, idx)
      |> put_new_action(:insert)
      |> check_action!(allowed_actions)}
  end

  defp do_cast(relation, _owner, nil = _params, current, _allowed_actions, _idx, _on_cast) do
    on_replace(relation, current)
  end

  defp do_cast(relation, _owner, params, struct, allowed_actions, idx, on_cast) do
    {:ok,
      relation
      |> apply_on_cast(on_cast, struct, params, idx)
      |> put_new_action(:update)
      |> check_action!(allowed_actions)}
  end

  defp apply_on_cast(%{cardinality: :many}, on_cast, struct, params, idx) when is_function(on_cast, 3) do
    on_cast.(struct, params, idx)
  end

  defp apply_on_cast(%{cardinality: :one, field: field}, on_cast, _struct, _params, _idx) when is_function(on_cast, 3) do
    raise ArgumentError, "invalid :with function for relation #{inspect(field)} " <>
      "of cardinality one. Expected a function of arity 2"
  end

  defp apply_on_cast(_relation, on_cast, struct, params, _idx) when is_function(on_cast, 2) do
    on_cast.(struct, params)
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
                                  &do_change(relation, &1, &2, &3, &4)) do
      {:error, {"is invalid", [type: expected_type(relation)]}}
    end
  end

  # This may be an insert or an update, get all fields.
  defp do_change(relation, %{__struct__: _} = changeset_or_struct, nil, _allowed_actions, _idx) do
    changeset = Changeset.change(changeset_or_struct)
    {:ok,
     changeset
     |> assert_changeset_struct!(relation)
     |> put_new_action(action_from_changeset(changeset, nil))}
  end

  defp do_change(relation, nil, current, _allowed_actions, _idx) do
    on_replace(relation, current)
  end

  defp do_change(relation, %Changeset{} = changeset, _current, allowed_actions, _idx) do
    {:ok,
     changeset
     |> assert_changeset_struct!(relation)
     |> put_new_action(:update)
     |> check_action!(allowed_actions)}
  end

  defp do_change(_relation, %{__struct__: _} = struct, _current, allowed_actions, _idx) do
    {:ok,
     struct
     |> Ecto.Changeset.change
     |> put_new_action(:update)
     |> check_action!(allowed_actions)}
  end

  defp do_change(relation, changes, current, allowed_actions, idx)
      when is_list(changes) or is_map(changes) do
    changeset = Ecto.Changeset.change(current || relation.__struct__.build(relation, nil), changes)
    changeset = put_new_action(changeset, action_from_changeset(changeset, current))
    do_change(relation, changeset, current, allowed_actions, idx)
  end

  defp action_from_changeset(%{data: %{__meta__: %{state: state}}}, _current) do
    case state do
      :built   -> :insert
      :loaded  -> :update
      :deleted -> :delete
    end
  end

  defp action_from_changeset(_, nil) do
    :insert
  end

  defp action_from_changeset(_, _current) do
    :update
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
    #{inspect owner} but the `:on_replace` option of this relation
    is set to `:raise`.

    By default it is not possible to replace or delete embeds and
    associations during `cast`. Therefore Ecto requires the parameters
    given to `cast` to have IDs matching the data currently associated
    to #{inspect owner}. Failing to do so results in this error message.

    If you want to replace data or automatically delete any data
    not sent to `cast`, please set the appropriate `:on_replace`
    option when defining the relation. The docs for `Ecto.Changeset`
    covers the supported options in the "Associations, embeds and on
    replace" section.

    However, if you don't want to allow data to be replaced or
    deleted, only updated, make sure that:

      * If you are attempting to update an existing entry, you
        are including the entry primary key (ID) in the data.

      * If you have a relationship with many children, all children
        must be given on update.

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
    {current_pks, current_map} = process_current(current, current_pks_fun, relation)
    %{unique: unique, ordered: ordered, related: mod} = relation
    change_pks_fun = change_pk(mod.__schema__(:primary_key))
    ordered = if ordered, do: current_pks, else: []
    map_changes(value, new_pks_fun, change_pks_fun, fun, current_map, [], true, true, unique && %{}, 0, ordered)
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
    case fun.(new, current, allowed_actions, nil) do
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

  defp map_changes([changes | rest], new_pks, change_pks, fun, current, acc, valid?, skip?, unique, idx, ordered)
      when is_map(changes) or is_list(changes) do
    pk_values = new_pks.(changes)
    {struct, current, allowed_actions} = pop_current(current, pk_values)

    case fun.(changes, struct, allowed_actions, idx) do
      {:ok, %{action: :ignore}} ->
        ordered = pop_ordered(pk_values, ordered)
        map_changes(rest, new_pks, change_pks, fun, current, acc, valid?, skip?, unique, idx + 1, ordered)
      {:ok, changeset} ->
        pk_values = change_pks.(changeset)
        changeset = maybe_add_error_on_pk(changeset, pk_values, unique)
        acc = [changeset | acc]
        valid? = valid? and changeset.valid?
        skip? = (struct != nil) and skip? and skip?(changeset)
        unique = unique && Map.put(unique, pk_values, true)
        ordered = pop_ordered(pk_values, ordered)
        map_changes(rest, new_pks, change_pks, fun, current, acc, valid?, skip?, unique, idx + 1, ordered)
      :error ->
        :error
    end
  end

  defp map_changes([], _new_pks, _change_pks, fun, current, acc, valid?, skip?, _unique, _idx, ordered) do
    current_structs = Enum.map(current, &elem(&1, 1))
    skip? = skip? and ordered == []
    reduce_delete_changesets(current_structs, fun, Enum.reverse(acc), valid?, skip?)
  end

  defp map_changes(_params, _new_pks, _change_pks, _fun, _current, _acc, _valid?, _skip?, _unique, _idx, _ordered) do
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
    case fun.(nil, struct, [:update, :delete], nil) do
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
        raise "cannot insert related #{inspect changeset.data} " <>
                "because it is already associated with the given struct"

      action == :replace ->
        raise "cannot replace related #{inspect changeset.data}. " <>
                "This typically happens when you are calling put_assoc/put_embed " <>
                "with the results of a previous put_assoc/put_embed/cast_assoc/cast_embed " <>
                "operation, which is not supported. You must call such operations only once " <>
                "per embed/assoc, in order for Ecto to track changes efficiently"

      true ->
        raise "cannot #{action} related #{inspect changeset.data} because " <>
                "it already exists and it is not currently associated with the " <>
                "given struct. Ecto forbids casting existing records through " <>
                "the association field for security reasons. Instead, set " <>
                "the foreign key value accordingly"
    end
  end

  defp process_current(nil, _get_pks, _relation),
    do: {[], %{}}

  defp process_current(current, get_pks, relation) do
    {pks, {map, counter}} =
      Enum.map_reduce(current, {%{}, 0}, fn struct, {acc, counter} ->
        pks = get_pks.(struct)
        key = if pks == [], do: map_size(acc), else: pks
        {pks, {Map.put(acc, key, struct), counter + 1}}
      end)

    if map_size(map) != counter do
      Logger.warning """
      found duplicate primary keys for association/embed `#{inspect(relation.field)}` \
      in `#{inspect(relation.owner)}`. In case of duplicate IDs, only the last entry \
      with the same ID will be kept. Make sure that all entries in `#{inspect(relation.field)}` \
      have an ID and the IDs are unique between them
      """
    end

    {pks, map}
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

  defp change_pk(pks) do
    fn %Changeset{} = cs ->
      Enum.map(pks, fn pk ->
        case cs.changes do
          %{^pk => pk_value} -> pk_value
          _ -> Map.get(cs.data, pk)
        end
      end)
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

  ## Surface changes on insert

  def surface_changes(%{changes: changes, types: types} = changeset, struct, fields) do
    {changes, errors} =
      Enum.reduce fields, {changes, []}, fn field, {changes, errors} ->
        case {struct, changes, types} do
          # User has explicitly changed it
          {_, %{^field => _}, _} ->
            {changes, errors}

          # Handle associations specially
          {_, _, %{^field => {tag, embed_or_assoc}}} when tag in [:assoc, :embed] ->
            # This is partly reimplementing the logic behind put_relation
            # in Ecto.Changeset but we need to do it in a way where we have
            # control over the current value.
            value = not_loaded_to_empty(Map.get(struct, field))
            empty = empty(embed_or_assoc)
            case change(embed_or_assoc, value, empty) do
              {:ok, change, _} when change != empty ->
                {Map.put(changes, field, change), errors}
              {:error, error} ->
                {changes, [{field, error}]}
              _ -> # :ignore or ok with change == empty
                {changes, errors}
            end

          # Struct has a non nil value
          {%{^field => value}, _, %{^field => _}} when value != nil ->
            {Map.put(changes, field, value), errors}

          {_, _, _} ->
            {changes, errors}
        end
      end

    case errors do
      [] -> %{changeset | changes: changes}
      _  -> %{changeset | errors: errors ++ changeset.errors, valid?: false, changes: changes}
    end
  end

  defp not_loaded_to_empty(%NotLoaded{__cardinality__: cardinality}),
    do: cardinality_to_empty(cardinality)

  defp not_loaded_to_empty(loaded), do: loaded
end
