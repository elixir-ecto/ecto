defmodule Ecto.Changeset do
  @moduledoc """
  The fields are:

  * `valid?`      - Stores if the changeset is valid
  * `model`       - The changeset root model
  * `params`      - The parameters as given on changeset creation
  * `changes`     - The `changes` from parameters that were approved in casting
  * `errors`      - All errors from validations
  * `validations` - All validations performed in the changeset
  """

  defstruct valid?: false, model: nil, params: nil, changes: %{},
            errors: [], validations: []

  @type t :: %Ecto.Changeset{valid?: boolean(),
                             model: Ecto.Model.t | nil,
                             params: %{String.t => term} | nil,
                             changes: %{atom => term},
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
  # TODO: Allow nil model
  @spec cast(map, Ecto.Model.t, [String.t], [String.t]) :: t
  def cast(params, %{__struct__: module} = model, required, optional)
      when is_map(params) and is_list(required) and is_list(optional) do
    types = module.__changeset__

    {changes, errors} =
      Enum.reduce(optional, {%{}, []},
                  &process_optional(&1, params, types, &2))

    {changes, errors, validations} =
      Enum.reduce(required, {changes, errors, []},
                  &process_required(&1, params, types, model, &2))

    %Ecto.Changeset{params: params, model: model,
                    valid?: errors == [], errors: errors,
                    validations: validations, changes: changes}
  end

  defp process_required(key, params, types, model, {changes, errors, validations}) do
    {key, param_key} = cast_key(key)
    validations = [{key, :required}|validations]
    type = type!(types, key)

    {changes, errors} =
      case cast_field(param_key, type, params) do
        {:ok, value} ->
          {Map.put(changes, key, value), error_on_blank(type, key, value, errors)}
        :missing ->
          value = Map.get(model, key)
          {changes, error_on_blank(type, key, value, errors)}
        :invalid ->
          {changes, [{key, :invalid}|errors]}
      end

    {changes, errors, validations}
  end

  defp process_optional(key, params, types, {changes, errors}) do
    {key, param_key} = cast_key(key)
    type = type!(types, key)

    case cast_field(param_key, type, params) do
      {:ok, value} ->
        {Map.put(changes, key, value), errors}
      :missing ->
        {changes, errors}
      :invalid ->
        {changes, [{key, :invalid}|errors]}
    end
  end

  defp type!(types, key),
    do: Map.get(types, key) || raise ArgumentError, "unknown field `#{key}`"

  defp cast_key(key) when is_binary(key),
    do: {String.to_atom(key), key}

  defp cast_field(param_key, type, params) do
    case Map.fetch(params, param_key) do
      {:ok, value} ->
        case Ecto.Types.cast(type, value) do
          {:ok, value} -> {:ok, value}
          :error       -> :invalid
        end
      :error ->
        :missing
    end
  end

  defp error_on_blank(type, key, value, errors) do
    if Ecto.Types.blank?(type, value) do
      [{key, :blank}|errors]
    else
      errors
    end
  end
end
