defmodule Ecto.Changeset do
  @moduledoc """
  Changesets allow filtering, casting and validation of model changes.

  There is an example of working with changesets in the introductory
  documentation in the `Ecto` module.

  ## The Ecto.Changeset struct

  The fields are:

  * `valid?`      - Stores if the changeset is valid
  * `repo`        - The repository applying the changeset (only set after a Repo function is called)
  * `model`       - The changeset root model
  * `params`      - The parameters as given on changeset creation
  * `changes`     - The `changes` from parameters that were approved in casting
  * `errors`      - All errors from validations
  * `validations` - All validations performed in the changeset
  * `required`    - All required fields as a list of atoms
  * `optional`    - All optional fields as a list of atoms
  * `filters`     - Filters (as a map `%{field => value}`) to narrow the scope of update/delete queries
  """

  alias __MODULE__

  import Ecto.Query, only: [from: 2]

  defstruct valid?: false, model: nil, params: nil, changes: %{}, repo: nil,
            errors: [], validations: [], required: [], optional: [],
            filters: %{}

  @type t :: %Changeset{valid?: boolean(),
                        repo: atom | nil,
                        model: Ecto.Model.t | nil,
                        params: %{String.t => term} | nil,
                        changes: %{atom => term},
                        required: [atom],
                        optional: [atom],
                        errors: [error],
                        validations: [{atom, String.t | {String.t, [term]}}],
                        filters: %{atom => term}}

  @type error :: {atom, error_message}
  @type error_message :: String.t | {String.t, integer}

  @number_validators %{
    less_than:                {&</2,  "must be less than %{count}"},
    greater_than:             {&>/2,  "must be greater than %{count}"},
    less_than_or_equal_to:    {&<=/2, "must be less than or equal to %{count}"},
    greater_than_or_equal_to: {&>=/2, "must be greater than or equal to %{count}"},
    equal_to:                 {&==/2, "must be equal to %{count}"},
  }

  @doc """
  Wraps the given model in a changeset or adds changes to a changeset.

  Changed attributes will only be added if the change does not have the
  same value as the attribute in the model.

  This function is useful for:

    * wrapping a model inside a changeset
    * directly changing the model without performing castings nor validations
    * directly bulk-adding changes to a changeset

  Since no validation nor casting is performed, `change/2` expects the keys in
  `changes` to be atoms. `changes` can be a map as well as a keyword list.

  When a changeset is passed as the first argument, the changes passed as the
  second argument are merged over the changes already in the changeset if they
  differ from the values in the model. If `changes` is an empty map, this
  function is a no-op.

  See `cast/4` if you'd prefer to cast and validate external parameters.

  ## Examples

      iex> changeset = change(%Post{})
      %Ecto.Changeset{...}
      iex> changeset.valid?
      true
      iex> changeset.changes
      %{}

      iex> changeset = change(%Post{author: "bar"}, title: "title")
      iex> changeset.changes
      %{title: "title"}

      iex> changeset = change(%Post{title: "title"}, title: "title")
      iex> changeset.changes
      %{}

      iex> changeset = change(changeset, %{title: "new title", body: "body"})
      iex> changeset.changes.title
      "new title"
      iex> changeset.changes.body
      "body"

  """
  @spec change(Ecto.Model.t | t, %{atom => term} | [Keyword.t]) :: t
  def change(model_or_changeset, changes \\ %{})

  def change(model_or_changeset, changes) when is_list(changes) do
    change(model_or_changeset, Enum.into(changes, %{}))
  end

  def change(%Changeset{changes: changes} = changeset, new_changes)
      when is_map(new_changes) do
    %{changeset | changes: get_changed(changeset.model, changes, new_changes)}
  end

  def change(%{__struct__: _} = model, changes) when is_map(changes) do
    changed = get_changed(model, %{}, changes)
    %Changeset{valid?: true, model: model, changes: changed}
  end

  defp get_changed(model, old_changes, new_changes) do
    Enum.reduce(new_changes, old_changes, fn({key, value}, acc) ->
      put_change(model, acc, key, value)
    end)
  end

  @doc """
  Converts the given `params` into a changeset for `model`
  keeping only the set of `required` and `optional` keys.

  This functions receives a model and some `params`, and casts the `params`
  according to the schema information from `model`. `params` is a map with
  string keys or a map with atom keys containing potentially unsafe data.

  During casting, all valid parameters will have their key name converted to an
  atom and stored as a change in the `:changes` field of the changeset.
  All parameters that are not listed in `required` or `optional` are ignored.

  If casting of all fields is successful and all required fields
  are present either in the model or in the given params, the
  changeset is returned as valid.

  ## Empty parameters

  The `params` argument can also be the atom `:empty`. In such cases, the
  changeset is automatically marked as invalid, with an empty `:changes` map.
  This is useful to run the changeset through all validation steps for
  introspection.

  ## Composing casts

  `cast/4` also accepts a changeset instead of a model as its first argument.
  In such cases, all the effects caused by the call to `cast/4` (additional and
  optional fields, errors and changes) are simply added to the ones already
  present in the argument changeset. Parameters are merged (**not deep-merged**)
  and the ones passed to `cast/4` take precedence over the ones already in the
  changeset.

  Note that if a field is marked both as *required* as well as *optional* (for
  example by being in the `:required` field of the argument changeset and also
  in the `optional` list passed to `cast/4`), then it will be marked as required
  and not optional). This represents the fact that required fields are
  "stronger" than optional fields.

  ## Examples

      iex> changeset = cast(post, params, ~w(title), ~w())
      iex> if changeset.valid? do
      ...>   Repo.update!(changeset)
      ...> end

  Passing a changeset as the first argument:

      iex> changeset = cast(post, %{title: "Hello"}, ~w(), ~w(title))
      iex> new_changeset = cast(changeset, %{title: "Foo", body: "Bar"}, ~w(title), ~w(body))
      iex> new_changeset.params
      %{title: "Foo", body: "Bar"}
      iex> new_changeset.required
      [:title]
      iex> new_changeset.optional
      [:body]

  """
  @spec cast(Ecto.Model.t | t,
             %{binary => term} | %{atom => term} | nil,
             [String.t | atom],
             [String.t | atom]) :: t
  def cast(model_or_changeset, params, required, optional \\ [])

  def cast(_model, %{__struct__: _} = params, _required, _optional) do
    raise ArgumentError, "expected params to be a map, got struct `#{inspect params}`"
  end

  def cast(%{__struct__: _} = model, :empty, required, optional)
      when is_list(required) and is_list(optional) do
    to_atom = fn
      key when is_atom(key) -> key
      key when is_binary(key) -> String.to_atom(key)
    end

    required = Enum.map(required, to_atom)
    optional = Enum.map(optional, to_atom)

    %Changeset{params: nil, model: model, valid?: false, errors: [],
               changes: %{}, required: required, optional: optional}
  end

  def cast(%Changeset{} = changeset, %{} = params, required, optional)
      when is_list(required) and is_list(optional) do
    new_changeset = cast(changeset.model, params, required, optional)
    merge(changeset, new_changeset)
  end

  def cast(%{__struct__: module} = model, %{} = params, required, optional)
      when is_list(required) and is_list(optional) do
    params = convert_params(params)
    types  = module.__changeset__

    {optional, {changes, errors}} =
      Enum.map_reduce(optional, {%{}, []},
                      &process_param(&1, :optional, params, types, model, &2))

    {required, {changes, errors}} =
      Enum.map_reduce(required, {changes, errors},
                      &process_param(&1, :required, params, types, model, &2))

    %Changeset{params: params, model: model, valid?: errors == [],
               errors: Enum.reverse(errors), changes: changes, required: required,
               optional: optional}
  end

  defp process_param(key, kind, params, types, model, {changes, errors}) do
    {key, param_key} = cast_key(key)
    current = Map.get(model, key)
    type = type!(types, key)

    {key,
      case cast_field(param_key, type, params) do
        {:ok, ^current} ->
          {changes, error_on_nil(kind, key, current, errors)}
        {:ok, value} ->
          {Map.put(changes, key, value), error_on_nil(kind, key, value, errors)}
        :missing ->
          {changes, error_on_nil(kind, key, current, errors)}
        :invalid ->
          {changes, [{key, "is invalid"}|errors]}
      end}
  end

  defp type!(types, key),
    do: Map.get(types, key) ||
          raise ArgumentError, "unknown field `#{key}` (note only fields are supported in cast, associations are not)"

  defp cast_key(key) when is_binary(key),
    do: {String.to_atom(key), key}
  defp cast_key(key) when is_atom(key),
    do: {key, Atom.to_string(key)}

  defp cast_field(param_key, :binary_id, params) do
    # Since we don't have the adapter types here,
    # we can't normalize the binary_id, so we just
    # assume it is a binary.
    cast_field(param_key, :binary, params)
  end

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

  defp convert_params(params) do
    Enum.reduce(params, nil, fn
      {key, _value}, nil when is_binary(key) ->
        nil

      {key, _value}, _ when is_binary(key) ->
        raise ArgumentError, "expected params to be a map with atoms or string keys, " <>
                             "got a map with mixed keys: #{inspect params}"

      {key, value}, acc when is_atom(key) ->
        Map.put(acc || %{}, Atom.to_string(key), value)

    end) || params
  end

  defp error_on_nil(:required, key, nil, errors),
    do: [{key, "can't be blank"}|errors]
  defp error_on_nil(_kind, _key, _value, errors),
    do: errors

  ## Working with changesets

  @doc """
  Merges two changesets.

  This function merges two changesets provided they have been applied to the
  same model (their `:model` field is equal); if the models differ, an
  `ArgumentError` exception is raised. If one of the changesets has a `:repo`
  field which is not `nil`, then the value of that field is used as the `:repo`
  field of the resulting changeset; if both changesets have a non-`nil` and
  different `:repo` field, an `ArgumentError` exception is raised.

  The other fields are merged with the following criteria:

  * `params` - params are merged (not deep-merged) giving precedence to the
    params of `changeset2` in case of a conflict. If either changeset has its
    `:params` field set to `nil`, the resulting changeset will have its params
    set to `nil` too.
  * `changes` - changes are merged giving precedence to the `changeset2`
    changes.
  * `errors` and `validations` - they are simply concatenated.
  * `required` and `optional` - they are merged; all the fields that appear
    in the optional list of either changesets and also in the required list of
    the other changeset are moved to the required list of the resulting
    changeset.

  ## Examples

      iex> changeset1 = cast(%{title: "Title"}, %Post{}, ~w(title), ~w(body))
      iex> changeset2 = cast(%{title: "New title", body: "Body"}, %Post{}, ~w(title body), ~w())
      iex> changeset = merge(changeset1, changeset2)
      iex> changeset.changes
      %{body: "Body", title: "New title"}
      iex> changeset.required
      [:title, :body]
      iex> changeset.optional
      []

      iex> changeset1 = cast(%{title: "Title"}, %Post{body: "Body"}, ~w(title), ~w(body))
      iex> changeset2 = cast(%{title: "New title"}, %Post{}, ~w(title), ~w())
      iex> merge(changeset1, changeset2)
      ** (ArgumentError) different models when merging changesets

  """
  @spec merge(t, t) :: t
  def merge(changeset1, changeset2)

  def merge(%Changeset{model: model, repo: repo1} = cs1, %Changeset{model: model, repo: repo2} = cs2)
      when is_nil(repo1) or is_nil(repo2) or repo1 == repo2 do
    new_repo        = repo1 || repo2
    new_params      = cs1.params && cs2.params && Map.merge(cs1.params, cs2.params)
    new_changes     = Map.merge(cs1.changes, cs2.changes)
    new_validations = cs1.validations ++ cs2.validations
    new_errors      = cs1.errors ++ cs2.errors
    new_required    = Enum.uniq(cs1.required ++ cs2.required)
    new_optional    = Enum.uniq(cs1.optional ++ cs2.optional) -- new_required

    %Changeset{params: new_params, model: model, valid?: new_errors == [],
               errors: new_errors, changes: new_changes, repo: new_repo,
               required: new_required, optional: new_optional,
               validations: new_validations}
  end

  def merge(%Changeset{model: m1}, %Changeset{model: m2}) when m1 != m2 do
    raise ArgumentError, message: "different models when merging changesets"
  end

  def merge(%Changeset{repo: r1}, %Changeset{repo: r2}) when r1 != r2 do
    raise ArgumentError, message: "different repos when merging changesets"
  end

  @doc """
  Fetches the given field from changes or from the model.

  While `fetch_change/2` only looks at the current `changes`
  to retrieve a value, this function looks at the changes and
  then falls back on the model, finally returning `:error` if
  no value is available.

  ## Examples

      iex> post = %Post{title: "Foo", body: "Bar baz bong"}
      iex> changeset = change(post, %{title: "New title"})
      iex> fetch_field(changeset, :title)
      {:changes, "New title"}
      iex> fetch_field(changeset, :body)
      {:model, "Bar baz bong"}
      iex> fetch_field(changeset, :not_a_field)
      :error

  """
  @spec fetch_field(t, atom) :: {:changes, term} | {:model, term} | :error
  def fetch_field(%{changes: changes, model: model} = _changeset, key) do
    case Map.fetch(changes, key) do
      {:ok, value} -> {:changes, value}
      :error ->
        case Map.fetch(model, key) do
          {:ok, value} -> {:model, value}
          :error       -> :error
        end
    end
  end

  @doc """
  Gets a field from changes or from the model.

  While `get_change/3` only looks at the current `changes`
  to retrieve a value, this function looks at the changes and
  then falls back on the model, finally returning `default` if
  no value is available.

      iex> post = %Post{title: "A title", body: "My body is a cage"}
      iex> changeset = change(post, %{title: "A new title"})
      iex> get_field(changeset, :title)
      "A new title"
      iex> get_field(changeset, :not_a_field, "Told you, not a field!")
      "Told you, not a field!"

  """
  @spec get_field(t, atom, term) :: term
  def get_field(%Changeset{changes: changes, model: model} = _changeset, key, default \\ nil) do
    case Map.fetch(changes, key) do
      {:ok, value} -> value
      :error ->
        case Map.fetch(model, key) do
          {:ok, value} -> value
          :error       -> default
        end
    end
  end

  @doc """
  Fetches a change from the given changeset.

  This function only looks at the `:changes` field of the given `changeset` and
  returns `{:ok, value}` if the change is present or `:error` if it's not.

  ## Examples

      iex> changeset = change(%Post{body: "foo"}, %{title: "bar"})
      iex> fetch_change(changeset, :title)
      {:ok, "bar"}
      iex> fetch_change(changeset, :body)
      :error

  """
  @spec fetch_change(t, atom) :: {:ok, term} | :error
  def fetch_change(%Changeset{changes: changes} = _changeset, key) when is_atom(key) do
    Map.fetch(changes, key)
  end

  @doc """
  Gets a change or returns a default value.

  ## Examples

      iex> changeset = change(%Post{body: "foo"}, %{title: "bar"})
      iex> get_change(changeset, :title)
      "bar"
      iex> get_change(changeset, :body)
      nil

  """
  @spec get_change(t, atom, term) :: term
  def get_change(%Changeset{changes: changes} = _changeset, key, default \\ nil) when is_atom(key) do
    Map.get(changes, key, default)
  end

  @doc """
  Updates a change.

  The given `function` is invoked with the change value only if there
  is a change for the given `key`. Note that the value of the change
  can still be `nil` (unless the field was marked as required on `cast/4`).

  ## Examples

      iex> changeset = change(%Post{}, %{impressions: 1})
      iex> changeset = update_change(changeset, :impressions, &(&1 + 1))
      iex> changeset.changes.impressions
      2

  """
  @spec update_change(t, atom, (term -> term)) :: t
  def update_change(%Changeset{changes: changes} = changeset, key, function) when is_atom(key) do
    case Map.fetch(changes, key) do
      {:ok, value} ->
        changes = Map.put(changes, key, function.(value))
        %{changeset | changes: changes}
      :error ->
        changeset
    end
  end

  @doc """
  Puts a change on the given `key` with `value`.

  If the change is already present, it is overridden with
  the new value, also, if the change has the same value as
  the model, it is not added to the list of changes.

  ## Examples

      iex> changeset = change(%Post{author: "bar"}, %{title: "foo"})
      iex> changeset = put_change(changeset, :title, "bar")
      iex> changeset.changes
      %{title: "bar"}

      iex> changeset = put_change(changeset, :author, "bar")
      iex> changeset.changes
      %{title: "bar"}

  """
  @spec put_change(t, atom, term) :: t
  def put_change(%Changeset{} = changeset, key, value) do
    update_in changeset.changes, &put_change(changeset.model, &1, key, value)
  end

  defp put_change(model, acc, key, value) do
    cond do
      Map.get(model, key) != value ->
        Map.put(acc, key, value)
      Map.has_key?(acc, key) ->
        Map.delete(acc, key)
      true ->
        acc
    end
  end

  @doc """
  Puts a change on the given `key` with `value`.

  If the change is already present, it is overridden with
  the new value.

  ## Examples

      iex> changeset = change(%Post{author: "bar"}, %{title: "foo"})
      iex> changeset = put_change(changeset, :title, "bar")
      iex> changeset.changes
      %{title: "bar"}

      iex> changeset = put_change(changeset, :author, "bar")
      iex> changeset.changes
      %{title: "bar", author: "bar"}

  """
  @spec force_change(t, atom, term) :: t
  def force_change(%Changeset{} = changeset, key, value) do
    update_in changeset.changes, &Map.put(&1, key, value)
  end

  @doc """
  Puts a change on the given `key` only if a change with that key doesn't
  already exist, also, if the change has the same value as the model, it
  is not added to the list of changes.

  ## Examples

      iex> changeset = change(%Post{author: "bar"}, %{})
      iex> changeset = put_new_change(changeset, :title, "foo")
      iex> changeset.changes
      %{title: "foo"}

      iex> changeset = put_new_change(changeset, :title, "bar")
      iex> changeset.changes
      %{title: "foo"}

      iex> changeset = put_new_change(changeset, :author, "bar")
      iex> changeset.changes
      %{title: "foo"}

  """
  @spec put_new_change(t, atom, term) :: t
  def put_new_change(%Changeset{} = changeset, key, value) do
    if Map.get(changeset.model, key) == value do
      changeset
    else
      update_in changeset.changes, &Map.put_new(&1, key, value)
    end
  end

  @doc """
  Deletes a change with the given key.

  ## Examples

      iex> changeset = change(%Post{}, %{title: "foo"})
      iex> changeset = delete_change(changeset, :title)
      iex> get_change(changeset, :title)
      nil

  """
  @spec delete_change(t, atom) :: t
  def delete_change(%Changeset{} = changeset, key) do
    update_in changeset.changes, &Map.delete(&1, key)
  end

  @doc """
  Applies the changeset changes to the changeset model.

  Note this operation is automatically performed on `Ecto.Repo.insert!/2` and
  `Ecto.Repo.update!/2`, however this function is provided for
  debugging and testing purposes.

  ## Examples

      apply_changes(changeset)

  """
  @spec apply_changes(t) :: Ecto.Model.t
  def apply_changes(%Changeset{changes: changes, model: model} = _changeset) do
    struct(model, changes)
  end

  ## Validations

  @doc """
  Adds an error to the changeset.

  ## Examples

      iex> changeset = change(%Post{}, %{title: ""})
      iex> changeset = add_error(changeset, :title, "empty")
      iex> changeset.errors
      [title: "empty"]
      iex> changeset.valid?
      false

  """
  @spec add_error(t, atom, error_message) :: t
  def add_error(%{errors: errors} = changeset, key, error) do
    %{changeset | errors: [{key, error}|errors], valid?: false}
  end

  @doc """
  Validates the given `field` change.

  It invokes the `validator` function to perform the validation
  only if a change for the given `field` exists and the change
  value is not `nil`. The function must return a list of errors (with an
  empty list meaning no errors).

  In case there's at least one error, the list of errors will be appended to the
  `:errors` field of the changeset and the `:valid?` flag will be set to
  `false`.

  ## Examples

      iex> changeset = change(%Post{}, %{title: "foo"})
      iex> changeset = validate_change changeset, :title, fn
      ...>   # Value must not be "foo"!
      ...>   :title, "foo" -> [title: "is_foo"]
      ...>   :title, _     -> []
      ...> end
      iex> changeset.errors
      [title: "is_foo"]

  """
  @spec validate_change(t, atom, (atom, term -> [error])) :: t
  def validate_change(changeset, field, validator) when is_atom(field) do
    %{changes: changes, errors: errors} = changeset

    new =
      if value = Map.get(changes, field), do: validator.(field, value), else: []

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

  ## Examples

      iex> changeset = change(%Post{}, %{title: "foo"})
      iex> changeset = validate_change changeset, :title, :useless_validator, fn
      ...>   _, _ -> []
      ...> end
      iex> changeset.validations
      [title: :useless_validator]

  """
  @spec validate_change(t, atom, any, (atom, term -> [error])) :: t
  def validate_change(%{validations: validations} = changeset, field, metadata, validator) do
    changeset = %{changeset | validations: [{field, metadata}|validations]}
    validate_change(changeset, field, validator)
  end

  @doc """
  Validates a change has the given format.

  The format has to be expressed as a regular expression.

  ## Options

    * `:message` - the message on failure, defaults to "has invalid format"

  ## Examples

      validate_format(changeset, :email, ~r/@/)

  """
  @spec validate_format(t, atom, Regex.t) :: t
  def validate_format(changeset, field, format, opts \\ []) do
    validate_change changeset, field, {:format, format}, fn _, value ->
      if value =~ format, do: [], else: [{field, message(opts, "has invalid format")}]
    end
  end

  @doc """
  Validates a change is included in the given enumerable.

  ## Options

    * `:message` - the message on failure, defaults to "is invalid"

  ## Examples

      validate_inclusion(changeset, :gender, ["man", "woman", "other", "prefer not to say"])
      validate_inclusion(changeset, :age, 0..99)

  """
  @spec validate_inclusion(t, atom, Enum.t) :: t
  def validate_inclusion(changeset, field, data, opts \\ []) do
    validate_change changeset, field, {:inclusion, data}, fn _, value ->
      if value in data, do: [], else: [{field, message(opts, "is invalid")}]
    end
  end

  @doc """
  Validates a change, of type enum, is a subset of the given enumerable. Like
  validate_inclusion/4 for lists.

  ## Options

    * `:message` - the message on failure, defaults to "\#{x} is invalid"

  ## Examples

      validate_subset(changeset, :pets, ["cat", "dog", "parrot"])
      validate_subset(changeset, :lottery_numbers, 0..99)

  """
  @spec validate_subset(t, atom, Enum.t) :: t
  def validate_subset(changeset, field, data, opts \\ []) do
    validate_change changeset, field, {:subset, data}, fn _, value ->
      case Enum.any?(value, fn(x) -> not x in data end) do
        true -> [{field, message(opts, "has an invalid entry")}]
        false -> []
      end
    end
  end

  @doc """
  Validates a change is not included in given the enumerable.

  ## Options

    * `:message` - the message on failure, defaults to "is reserved"

  ## Examples

      validate_exclusion(changeset, :name, ~w(admin superadmin))

  """
  @spec validate_exclusion(t, atom, Enum.t) :: t
  def validate_exclusion(changeset, field, data, opts \\ []) do
    validate_change changeset, field, {:exclusion, data}, fn _, value ->
      if value in data, do: [{field, message(opts, "is reserved")}], else: []
    end
  end

  @doc """
  Validates the given `field`'s uniqueness on the given repository.

  The validation runs if the field (or any of the values given in
  scope) has changed and none of them contain an error. For this
  reason, you may want to trigger the unique validations as last
  in your validation pipeline.

  ## Examples

      validate_unique(changeset, :email, on: Repo)

  ## Options

    * `:message` - the message on failure, defaults to "has already been taken"
    * `:on` - the repository to perform the query on
    * `:downcase` - when `true`, downcase values when performing the uniqueness query
    * `:scope` - a list of other fields to use for the uniqueness query

  ## Case sensitivity

  Unfortunately, different databases provide different guarantees
  when it comes to case-sensitiveness. For example, in MySQL, comparisons
  are case-insensitive by default. In Postgres, users can define case
  insensitive column by using the `:citext` type/extension.

  These behaviours make it hard for Ecto to guarantee if the unique
  validation is case insensitive or not and that's why Ecto **does not**
  provide a `:case_sensitive` option.

  However `validate_unique/3` does provide a `:downcase` option that
  guarantees values are downcased when doing the uniqueness check.
  When this option is set, values are downcased regardless of the
  database being used.

  Since the `:downcase` option downcases the database values on the
  fly, it should be used with care as it may affect performance. For example,
  if this option is used, it could be appropriate to create an index with the
  downcased value. Using `Ecto.Migration` syntax, one could write:

      create index(:posts, ["lower(title)"])

  Many times, however, it's simpler to just explicitly downcase values
  before inserting them into the database and avoid the `:downcase` option
  in `validate_unique/3`:

      cast(params, model, ~w(email), ~w())
      |> update_change(:email, &String.downcase/1)
      |> validate_unique(:email, on: Repo)

  ## Scope

  The `:scope` option allows specifying of other fields that are used to limit
  the uniqueness check. For example, if our use case limits a user to a single
  comment per blog post, it would look something like:

      cast(params, model, ~w(comment), ~w())
      |> validate_unique(:user_id, scope: [:post_id], on: Repo)

  """
  @spec validate_unique(t, atom, [Keyword.t]) :: t
  def validate_unique(changeset, field, opts) when is_list(opts) do
    %{model: model, changes: changes, errors: errors, validations: validations} = changeset
    changeset = %{changeset | validations: [{field, {:unique, opts}}|validations]}

    repo   = Keyword.fetch!(opts, :on)
    scope  = Keyword.get(opts, :scope)
    fields = [field|List.wrap(scope)]

    if Enum.any?(fields, &Map.has_key?(changes, &1)) &&
       Enum.all?(fields, &not Keyword.has_key?(errors, &1)) do
      struct = model.__struct__
      value  = Map.get(changes, field)
      query  = from m in struct, select: field(m, ^field), limit: 1

      if scope do
        query = Enum.reduce(scope, query, fn(field, acc) ->
          case get_field(changeset, field) do
            nil -> from m in acc, where: is_nil(field(m, ^field))
            v   -> from m in acc, where: field(m, ^field) == ^v
          end
        end)
      end

      query =
        cond do
          value == nil ->
            from m in query, where: is_nil(field(m, ^field))
          opts[:downcase] ->
            from m in query, where:
              fragment("lower(?)", field(m, ^field)) == fragment("lower(?)", ^value)
          true ->
            from m in query, where: field(m, ^field) == ^value
        end

      query =
        Enum.reduce(Ecto.Model.primary_key!(model), query, fn
          {_, nil}, acc -> acc
          {k, v}, acc   -> from m in acc, where: field(m, ^k) != ^v
        end)

      case repo.all(query) do
        []  -> changeset
        [_] -> add_error(changeset, field, message(opts, "has already been taken"))
      end
    else
      changeset
    end
  end

  @doc """
  Validates a change is a string of the given length.

  ## Options

    * `:is` - the string length must be exactly this value
    * `:min` - the string length must be greater than or equal to this value
    * `:max` - the string lenght must be less than or equal to this value
    * `:message` - the message on failure, depending on the validation, is one of:
      * "should be %{count} characters"
      * "should be at least %{count} characters"
      * "should be at most %{count} characters"

  ## Examples

      validate_length(changeset, :title, min: 3)
      validate_length(changeset, :title, max: 100)
      validate_length(changeset, :title, min: 3, max: 100)
      validate_length(changeset, :code, is: 9)

  """
  @spec validate_length(t, atom, Keyword.t) :: t
  def validate_length(changeset, field, opts) when is_list(opts) do
    validate_change changeset, field, {:length, opts}, fn
      _, value when is_binary(value) ->
        length = String.length(value)
        error  = ((is = opts[:is]) && wrong_length(length, is, opts)) ||
                 ((min = opts[:min]) && too_short(length, min, opts)) ||
                 ((max = opts[:max]) && too_long(length, max, opts))
        if error, do: [{field, error}], else: []
    end
  end

  defp wrong_length(value, value, _opts), do: nil
  defp wrong_length(_length, value, opts), do:
    {message(opts, "should be %{count} characters"), value}

  defp too_short(length, value, _opts) when length >= value, do: nil
  defp too_short(_length, value, opts), do:
    {message(opts, "should be at least %{count} characters"), value}

  defp too_long(length, value, _opts) when length <= value, do: nil
  defp too_long(_length, value, opts), do:
    {message(opts, "should be at most %{count} characters"), value}

  @doc """
  Validates the properties of a number.

  ## Options

    * `:less_than`
    * `:greater_than`
    * `:less_than_or_equal_to`
    * `:greater_than_or_equal_to`
    * `:equal_to`
    * `:message` - the message on failure, defaults to one of:
      * "must be less than %{count}"
      * "must be greater than %{count}"
      * "must be less than or equal to %{count}"
      * "must be greater than or equal to %{count}"
      * "must be equal to %{count}"

  ## Examples

      validate_number(changeset, :count, less_than: 3)
      validate_number(changeset, :pi, greater_than: 3, less_than: 4)
      validate_number(changeset, :the_answer_to_life_the_universe_and_everything, equal_to: 42)

  """
  @spec validate_number(t, atom, Range.t | [Keyword.t]) :: t
  def validate_number(changeset, field, opts) do
    validate_change changeset, field, {:number, opts}, fn
      field, value ->
        Enum.find_value opts, [], fn {spec_key, target_value} ->
          validate_number(field, value, opts, spec_key, target_value)
        end
    end
  end

  defp validate_number(field, value, opts, spec_key, target_value) do
    case Map.fetch(@number_validators, spec_key) do
      {:ok, {spec_function, error_message}} ->
        case apply(spec_function, [value, target_value]) do
          true  -> nil
          false -> [{field, {message(opts, error_message), target_value}}]
        end
      _ -> nil # if the spec_key isn't in the validators_map just ignore it
    end
  end

  @doc """
  Validates that the given field matches the confirmation
  parameter of that field.

  By calling `validate_confirmation(changeset, :email)`, this
  validation will check if both "email" and "email_confirmation"
  in the parameter map matches.

  Note that this does not add a validation error if the confirmation
  field is nil. Note "email_confirmation" does not need to be added
  as a virtual field in your schema.

  ## Options

    * `:message` - the message on failure, defaults to "does not match"

  ## Examples

      validate_confirmation(changeset, :email)
      validate_confirmation(changeset, :password, message: "passwords do not match")

      cast(params, model, ~w(password), ~w())
      |> validate_confirmation(:password, message: "passwords do not match")

  """
  @spec validate_confirmation(t, atom, Enum.t) :: t
  def validate_confirmation(changeset, field, opts \\ []) do
    validate_change changeset, field, {:confirmation, opts}, fn _, _ ->
      param = Atom.to_string(field)
      value = Map.get(changeset.params, param)

      case Map.fetch(changeset.params, "#{param}_confirmation") do
        {:ok, ^value} -> []
        {:ok, _}      -> [{field, message(opts, "does not match confirmation")}]
        :error        -> []
      end
    end
  end

  defp message(opts, default) do
    Keyword.get(opts, :message, default)
  end
end
