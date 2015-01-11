defmodule Ecto.Changeset do
  @moduledoc """
  Changesets allow filtering, casting and validation of model changes.

  There is an example of working with changesets in the introductory
  documentation in the `Ecto` module.

  ## The Ecto.Changeset struct

  The fields are:

  * `valid?`      - Stores if the changeset is valid
  * `model`       - The changeset root model
  * `params`      - The parameters as given on changeset creation
  * `changes`     - The `changes` from parameters that were approved in casting
  * `errors`      - All errors from validations
  * `validations` - All validations performed in the changeset
  * `required`    - All required fields as a list of atoms
  * `optional`    - All optional fields as a list of atoms
  """

  defstruct valid?: false, model: nil, params: nil, changes: %{},
            errors: [], validations: [], required: [], optional: []

  @type t :: %Ecto.Changeset{valid?: boolean(),
                             model: Ecto.Model.t | nil,
                             params: %{String.t => term} | nil,
                             changes: %{atom => term},
                             required: [atom],
                             optional: [atom],
                             errors: [{atom, atom | {atom, [term]}}],
                             validations: [{atom, atom | {atom, [term]}}]}

  @doc """
  Converts the given `params` into a changeset for `model`
  keeping only the set of `required` and `optional` keys.

  This functions receives the `params` and cast them according
  to the schema information from `model`. `params` are a map
  with strings as key of potentially unsafe data.

  During casting, all valid parameters will have their key name
  converted to atoms and stored as a change in the changeset.
  All other parameters that are not listed in `required` or
  `optional` are ignored.

  If casting of all fields is successful and all required fields
  are present either in the model or in the given params, the
  changeset is returned as valid.
  """
  # TODO: Allow nil params
  # TODO: Allow no model
  # TODO: Add fetch_change and get_change
  @spec cast(map, Ecto.Model.t, [String.t | atom], [String.t | atom]) :: t
  def cast(params, %{__struct__: module} = model, required, optional)
      when is_map(params) and is_list(required) and is_list(optional) do
    types = module.__changeset__

    {optional, {changes, errors}} =
      Enum.map_reduce(optional, {%{}, []},
                      &process_optional(&1, params, types, &2))

    {required, {changes, errors}} =
      Enum.map_reduce(required, {changes, errors},
                      &process_required(&1, params, types, model, &2))

    %Ecto.Changeset{params: params, model: model, valid?: errors == [],
                    errors: errors, changes: changes, required: required,
                    optional: optional}
  end

  defp process_required(key, params, types, model, {changes, errors}) do
    {key, param_key} = cast_key(key)
    type = type!(types, key)

    {key,
      case cast_field(param_key, type, params) do
        {:ok, value} ->
          {Map.put(changes, key, value), error_on_blank(type, key, value, errors)}
        :missing ->
          value = Map.get(model, key)
          {changes, error_on_blank(type, key, value, errors)}
        :invalid ->
          {changes, [{key, :invalid}|errors]}
      end}
  end

  defp process_optional(key, params, types, {changes, errors}) do
    {key, param_key} = cast_key(key)
    type = type!(types, key)

    {key,
      case cast_field(param_key, type, params) do
        {:ok, value} ->
          {Map.put(changes, key, value), errors}
        :missing ->
          {changes, errors}
        :invalid ->
          {changes, [{key, :invalid}|errors]}
      end}
  end

  defp type!(types, key),
    do: Map.get(types, key) || raise ArgumentError, "unknown field `#{key}`"

  defp cast_key(key) when is_binary(key),
    do: {String.to_atom(key), key}
  defp cast_key(key) when is_atom(key),
    do: {key, Atom.to_string(key)}

  defp cast_field(param_key, type, params) do
    case Map.fetch(params, param_key) do
      {:ok, value} ->
        case Ecto.Type.cast(type, value) do
          {:ok, value} -> {:ok, value}
          :error       -> :invalid
        end
      :error ->
        :missing
    end
  end

  defp error_on_blank(type, key, value, errors) do
    if Ecto.Type.blank?(type, value) do
      [{key, :required}|errors]
    else
      errors
    end
  end

  ## Working with changesets

  @doc """
  Updates a change.

  The `function` is invoked with the change value only if there
  is a change for the given `key`. Notice the value of the change
  can still be nil (unless the field was marked as required on `cast/4`).
  """
  def update_change(%{changes: changes} = changeset, key, function) when is_atom(key) do
    case Map.fetch(changes, key) do
      {:ok, value} ->
        changes = Map.put(changes, key, function.(value))
        %{changeset | changes: changes}
      :error ->
        changeset
    end
  end

  @doc """
  Puts a change on the given key with value.
  """
  def put_change(changeset, key, value) do
    update_in changeset.changes, &Map.put(&1, key, value)
  end

  @doc """
  Deletes a change with the given key.
  """
  def delete_change(changeset, key) do
    update_in changeset.changes, &Map.delete(&1, key)
  end

  ## Validations

  @doc """
  Adds an error to the changeset.

  ## Examples

      add_error(changeset, :name, :invalid)

  """
  def add_error(%{errors: errors} = changeset, key, error) do
    %{changeset | errors: [{key, error}|errors], valid?: false}
  end

  @doc """
  Validates the given `field` change.

  It invokes the `validator` function to perform the validation
  only if a change for the given `field` exists and the change
  value is not nil. The function must a list of errors (empty
  meaning no errors).

  In case of at least one error, they will be stored in the
  `errors` field of the changeset and the `valid?` flag will
  be set to false.
  """
  def validate_change(changeset, field, validator) when is_atom(field) do
    %{changes: changes, errors: errors} = changeset

    new =
      if value = Map.get(changes, field), do: validator.(value), else: []

    case new do
      []    -> changeset
      [_|_] -> %{changeset | errors: new ++ errors, valid?: false}
    end
  end

  @doc """
  Stores the validation `metadata` and validates the given `field` change.

  Similar to `validate_change/3` but stores the validation metadata
  into the changeset validators. The validator metadata is often used
  as a reflection mechanism, to automatically generate code based on
  the available validations.
  """
  def validate_change(%{validations: validations} = changeset, field, metadata, validator) do
    changeset = %{changeset | validations: [{field, metadata}|validations]}
    validate_change(changeset, field, validator)
  end

  @doc """
  Validates a change has the given format.

  ## Examples

      validate_format(changeset, :email, ~r/@/)

  """
  def validate_format(changeset, field, format) do
    validate_change changeset, field, {:format, format}, fn value ->
      if value =~ format, do: [], else: [{field, :format}]
    end
  end

  @doc """
  Validates a change is included in the enumerable.

  ## Examples

      validate_inclusion(changeset, :gender, ["male", "female", "who cares?"])
      validate_inclusion(changeset, :age, 0..99)
  """
  def validate_inclusion(changeset, field, data) do
    validate_change changeset, field, {:inclusion, data}, fn value ->
      if value in data, do: [], else: [{field, :inclusion}]
    end
  end

  @doc """
  Validates a change is not in the enumerable.

  ## Examples

      validate_exclusion(changeset, :name, ~w(admin superadmin))

  """
  def validate_exclusion(changeset, field, data) do
    validate_change changeset, field, {:exclusion, data}, fn value ->
      if value in data, do: [{field, :exclusion}], else: []
    end
  end

  @doc """
  Validates a change is a string of the given length.

  ## Examples

      validate_length(changeset, :title, 3..100)
      validate_length(changeset, :title, min: 3)
      validate_length(changeset, :title, max: 100)
      validate_length(changeset, :code, is: 9)

  """
  def validate_length(changeset, field, min..max) when is_integer(min) and is_integer(max) do
    validate_length changeset, field, [min: min, max: max]
  end

  def validate_length(changeset, field, opts) when is_list(opts) do
    validate_change changeset, field, {:length, opts}, fn
      value when is_binary(value) ->
        length = String.length(value)
        error  = ((is = opts[:is]) && wrong_length(length, is)) ||
                 ((min = opts[:min]) && too_short(length, min)) ||
                 ((max = opts[:max]) && too_long(length, max))
        if error, do: [{field, error}], else: []
    end
  end

  defp wrong_length(value, value),   do: nil
  defp wrong_length(_length, value), do: {:wrong_length, value}

  defp too_short(length, value) when length >= value, do: nil
  defp too_short(_length, value), do: {:too_short, value}

  defp too_long(length, value) when length <= value, do: nil
  defp too_long(_length, value), do: {:too_long, value}
end
