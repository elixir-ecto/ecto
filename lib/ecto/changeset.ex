defmodule Ecto.Changeset do
  @moduledoc ~S"""
  Changesets allow filtering, casting, validation and
  definition of constraints when manipulating models.

  There is an example of working with changesets in the
  introductory documentation in the `Ecto` module. The
  functions `change/2` and `cast/4` are the usual entry
  points for creating changesets, while the remaining
  functions are useful for manipulating them.

  ## Validations and constraints

  Ecto changesets provide both validations and constraints
  which are ultimately turned into errors in case something
  goes wrong.

  The difference between them is that validations can be executed
  without a need to interact with the database and, therefore, are
  always executed before attemping to insert or update the entry
  in the database.

  However, constraints can only be checked in a safe way when performing
  the operation in the database. As a consequence, validations are
  always checked before constraints. Constraints won't even be
  checked in case validations failed.

  Let's see an example:

      defmodule User do
        use Ecto.Schema
        import Ecto.Changeset

        schema "users" do
          field :name
          field :email
          field :age, :integer
        end

        def changeset(user, params \\ :empty) do
          user
          |> cast(params, ~w(name email), ~w(age))
          |> validate_format(:email, ~r/@/)
          |> validate_inclusion(:age, 18..100)
          |> unique_constraint(:email)
        end
      end

  In the `changeset/2` function above, we define two validations -
  one for checking the e-mail format and another to check the age -
  as well as a unique constraint in the email field.

  Let's suppose the e-mail is given but the age is invalid.  The
  changeset would have the following errors:

      changeset = User.changeset(%User{}, %{age: 0, email: "mary@example.com"})
      {:error, changeset} = Repo.insert(changeset)
      changeset.errors #=> [age: "is invalid"]

  In this case, we haven't checked the unique constraint in the
  e-mail field because the data did not validate. Let's fix the
  age and assume, however, that the e-mail already exists in the
  database:

      changeset = User.changeset(%User{}, %{age: 42, email: "mary@example.com"})
      {:error, changeset} = Repo.insert(changeset)
      changeset.errors #=> [email: "has already been taken"]

  Validations and constraints define an explicit boundary when the check
  happens. By moving constraints to the database, we also provide a safe,
  correct and data-race free means of checking the user input.

  ## The Ecto.Changeset struct

  The fields are:

  * `valid?`      - Stores if the changeset is valid
  * `model`       - The changeset root model
  * `params`      - The parameters as given on changeset creation
  * `changes`     - The `changes` from parameters that were approved in casting
  * `errors`      - All errors from validations
  * `validations` - All validations performed in the changeset
  * `constraints` - All constraints defined in the changeset
  * `required`    - All required fields as a list of atoms
  * `filters`     - Filters (as a map `%{field => value}`) to narrow the scope of update/delete queries
  * `action`      - The action to be performed with the changeset
  * `types`       - Cache of the model's field types
  * `repo`        - The repository applying the changeset (only set after a Repo function is called)
  * `opts`        - The options given to the repository

  ## On replace

  Using changesets you can work with associations as well as with embedded
  structs. Sometimes related data may be replaced by incoming data and by
  default Ecto won't allow such. Such behaviour can be changed when defining
  the relation according to the values below:

    * `:raise` (default) - do not allow removing association or embedded
    model via parent changesets,
    * `:mark_as_invalid` - if attempting to remove the association or
    embedded model via parent changeset - an error will be added to the parent
    changeset, and it will be marked as invalid,
    * `:nilify` - sets owner reference column to `nil` (available only for
    associations),
    * `:delete` - removes the association or related model from the database.
    This option has to be used carefully. You should consider adding a
    separate boolean virtual field to your model that will alow to manually
    mark it deletion, as in the example below:

          defmodule Comment do
            use Ecto.Schema
            import Ecto.Changeset

            schema "comments" do
              field :body, :string
              field :delete, :boolean, virtual: true
            end

            def changeset(model, params) do
              cast(model, params, [:body], [:delete])
              |> maybe_mark_for_deletion
            end

            defp maybe_mark_for_deletion(changeset) do
              if get_change(changeset, :delete) do
                %{changeset | action: :delete}
              else
                changeset
              end
            end
          end

  """

  alias __MODULE__
  alias Ecto.Changeset.Relation

  # If a new field is added here, def merge must be adapted
  defstruct valid?: false, model: nil, params: nil, changes: %{}, repo: nil,
            errors: [], validations: [], required: [], prepare: [],
            constraints: [], filters: %{}, action: nil, types: nil

  @type t :: %Changeset{valid?: boolean(),
                        repo: atom | nil,
                        model: Ecto.Schema.t | nil,
                        params: %{String.t => term} | nil,
                        changes: %{atom => term},
                        required: [atom],
                        prepare: [(t -> t)],
                        errors: [error],
                        constraints: [constraint],
                        validations: Keyword.t,
                        filters: %{atom => term},
                        action: action,
                        types: nil | %{atom => Ecto.Type.t}}

  @type error :: {atom, error_message}
  @type error_message :: String.t | {String.t, Keyword.t}
  @type action :: nil | :insert | :update | :delete | :replace
  @type constraint :: %{type: :unique, constraint: String.t,
                        field: atom, message: error_message}

  @number_validators %{
    less_than:                {&</2,  "must be less than %{count}"},
    greater_than:             {&>/2,  "must be greater than %{count}"},
    less_than_or_equal_to:    {&<=/2, "must be less than or equal to %{count}"},
    greater_than_or_equal_to: {&>=/2, "must be greater than or equal to %{count}"},
    equal_to:                 {&==/2, "must be equal to %{count}"},
  }

  @relations [:embed, :assoc]

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
  @spec change(Ecto.Schema.t | t, %{atom => term} | Keyword.t) :: t | no_return
  def change(model_or_changeset, changes \\ %{})

  def change(%Changeset{types: nil}, _changes) do
    raise ArgumentError, "changeset does not have types information"
  end

  def change(%Changeset{changes: changes, types: types} = changeset, new_changes)
      when is_map(new_changes) or is_list(new_changes) do
    {changes, errors, valid?} =
      get_changed(changeset.model, types, changes, new_changes,
                  changeset.errors, changeset.valid?)
    %{changeset | changes: changes, errors: errors, valid?: valid?}
  end

  def change(%{__struct__: struct} = model, changes) when is_map(changes) or is_list(changes) do
    types = struct.__changeset__
    {changes, errors, valid?} =
      get_changed(model, types, %{}, changes, [], true)
    %Changeset{valid?: valid?, model: model, changes: changes,
               errors: errors, types: types}
  end

  defp get_changed(model, types, old_changes, new_changes, errors, valid?) do
    Enum.reduce(new_changes, {old_changes, errors, valid?}, fn
      {key, value}, {changes, errors, valid?} ->
        put_change(model, changes, errors, valid?, key, value, Map.get(types, key))
    end)
  end

  @doc """
  Converts the given `params` into a changeset for `model`
  keeping only the set of `required` and `optional` keys.

  This function receives a model and some `params`, and casts the `params`
  according to the schema information from `model`. `params` is a map with
  string keys or a map with atom keys containing potentially unsafe data.

  During casting, all valid parameters will have their key name converted to an
  atom and stored as a change in the `:changes` field of the changeset.
  All parameters that are not listed in `required` or `optional` are ignored.

  If casting of all fields is successful and all required fields
  are present either in the model or in the given params, the
  changeset is returned as valid.

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

  ## Empty parameters

  The `params` argument can also be the atom `:empty`. In such cases, the
  changeset is automatically marked as invalid, with an empty `:changes` map.
  This is useful to run the changeset through all validation steps for
  introspection:

      iex> changeset = cast(post, :empty, ~w(title), ~w())
      iex> changeset = validate_length(post, :title, min: 3)
      iex> changeset.validations
      [title: [min: 3]]

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
  and not optional. This represents the fact that required fields are
  "stronger" than optional fields.
  """
  @spec cast(Ecto.Schema.t | t,
             %{binary => term} | %{atom => term} | nil,
             [String.t | atom],
             [String.t | atom]) :: t | no_return
  def cast(model_or_changeset, params, required, optional)

  def cast(_model, %{__struct__: _} = params, _required, _optional) do
    raise ArgumentError, "expected params to be a map, got struct `#{inspect params}`"
  end

  def cast(%Changeset{changes: changes, model: model} = changeset, params, required, optional) do
    new_changeset = cast(model, changes, params, required, optional)
    cast_merge(changeset, new_changeset)
  end

  def cast(%{__struct__: _} = model, params, required, optional) do
    cast(model, %{}, params, required, optional)
  end

  defp cast(%{__struct__: module} = model, %{} = changes, :empty, required, optional)
      when is_list(required) and is_list(optional) do
    types = module.__changeset__

    _ = Enum.map(optional, &process_empty_fields(&1, types))
    required = Enum.map(required, &process_empty_fields(&1, types))

    %Changeset{params: nil, model: model, valid?: false, errors: [],
               changes: changes, required: required, types: types}
  end

  defp cast(%{__struct__: module} = model, %{} = changes, %{} = params, required, optional)
      when is_list(required) and is_list(optional) do
    params = convert_params(params)
    types  = module.__changeset__

    {_, {changes, errors, valid?}} =
      Enum.map_reduce(optional, {changes, [], true},
                      &process_param(&1, :optional, params, types, model, &2))

    {required, {changes, errors, valid?}} =
      Enum.map_reduce(required, {changes, errors, valid?},
                      &process_param(&1, :required, params, types, model, &2))

    %Changeset{params: params, model: model, valid?: valid?,
               errors: Enum.reverse(errors), changes: changes, required: required,
               types: types}
  end

  defp process_empty_fields(key, _types) when is_binary(key) do
    String.to_existing_atom(key)
  end
  defp process_empty_fields(key, _types) when is_atom(key) do
    key
  end

  defp process_param(key, kind, params, types, model, {changes, errors, valid?}) do
    {key, param_key} = cast_key(key)
    type = type!(types, key)
    current = Map.get(model, key)

    {key,
     case cast_field(param_key, type, params, current, model, valid?) do
       {:ok, nil, valid?} when kind == :required ->
         {errors, valid?} = error_on_nil(kind, key, Map.get(changes, key), errors, valid?)
         {changes, errors, valid?}
       {:ok, value, valid?} ->
         {Map.put(changes, key, value), errors, valid?}
       {:missing, current} ->
         {errors, valid?} = error_on_nil(kind, key, Map.get(changes, key, current), errors, valid?)
         {changes, errors, valid?}
       :invalid ->
         {changes, [{key, "is invalid"}|errors], false}
     end}
  end

  defp type!(types, key) do
    case Map.fetch(types, key) do
      {:ok, {tag, _}} when tag in @relations ->
        raise "casting #{tag}s with cast/4 is not supported, use cast_#{tag}/3 instead"
      {:ok, type} ->
        type
      :error ->
        raise ArgumentError, "unknown field `#{key}` (note only fields, " <>
          "embeds, belongs_to, has_one and has_many associations are supported in changesets)"
    end
  end

  defp cast_key(key) when is_binary(key),
    do: {String.to_existing_atom(key), key}
  defp cast_key(key) when is_atom(key),
    do: {key, Atom.to_string(key)}

  defp cast_field(param_key, type, params, current, _model, valid?) do
    case Map.fetch(params, param_key) do
      {:ok, value} ->
        case Ecto.Type.cast(type, value) do
          {:ok, ^current} -> {:missing, current}
          {:ok, value} -> {:ok, value, valid?}
          :error -> :invalid
        end
      :error ->
        {:missing, current}
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

  defp error_on_nil(:required, key, nil, errors, _valid?),
    do: {[{key, "can't be blank"}|errors], false}
  defp error_on_nil(_kind, _key, _value, errors, valid?),
    do: {errors, valid?}

  ## Casting related

  @doc """
  Casts the given association.

  The parameters for the given association will be retrieved
  from `changeset.params` and the changeset function in the
  association module will be invoked. The function to be
  invoked may also be configured by using the `:with` option.

  The changeset must have been previously `cast` using
  `cast/4` before this function is invoked.

  ## Options

    * `:with` - the function to build the changeset from params.
      Defaults to the changeset/2 function in the association module
    * `:required` - if the association is a required field
  """
  def cast_assoc(changeset, name, opts \\ []) when is_atom(name) do
    cast_relation(:assoc, changeset, name, opts)
  end

  @doc """
  Casts the given embed.

  The parameters for the given embed will be retrieved
  from `changeset.params` and the changeset function in the
  embed module will be invoked. The function to be
  invoked may also be configured by using the `:with` option.

  The changeset must have been previously `cast` using
  `cast/4` before this function is invoked.

  ## Options

    * `:with` - the function to build the changeset from params.
      Defaults to the changeset/2 function in the embed module
    * `:required` - if the embed is a required field
  """
  def cast_embed(changeset, name, opts \\ []) when is_atom(name) do
    cast_relation(:embed, changeset, name, opts)
  end

  defp cast_relation(type, %Changeset{model: model, types: types}, _name, _opts)
      when model == nil or types == nil do
    raise ArgumentError, "cast_#{type}/3 expects the changeset to be cast. " <>
                         "Please call cast/4 before calling cast_#{type}/3"
  end

  defp cast_relation(type, %Changeset{} = changeset, key, opts) do
    {key, param_key} = cast_key(key)
    %{model: model, types: types, params: params, changes: changes} = changeset
    %{related: related} = relation = relation!(:cast, type, key, Map.get(types, key))
    params = params || %{}

    {changeset, required?} =
      if opts[:required] do
        {update_in(changeset.required, &[key|&1]), true}
      else
        {changeset, false}
      end

    on_cast = opts[:with] || &related.changeset(&1, &2)
    current = Relation.load!(model, Map.get(model, key))

    case Map.fetch(params, param_key) do
      {:ok, value} ->
        case Relation.cast(relation, value, current, on_cast) do
          {:ok, change, relation_valid?, false} when change != current ->
            missing_relation(%{changeset | changes: Map.put(changes, key, change),
                               valid?: changeset.valid? && relation_valid?}, key, current, required?, relation)
          {:ok, _, _, _} ->
            missing_relation(changeset, key, current, required?, relation)
          :error ->
            %{changeset | errors: [{key, "is invalid"} | changeset.errors], valid?: false}
        end
      :error ->
        missing_relation(changeset, key, current, required?, relation)
    end
  end

  defp missing_relation(%{changes: changes, errors: errors} = changeset, name, current, required?, relation) do
    current_changes = Map.get(changes, name, current)
    if required? and Relation.empty?(relation, current_changes) do
      %{changeset | errors: [{name, "can't be blank"} | errors], valid?: false}
    else
      changeset
    end
  end

  defp relation!(_op, type, _name, {type, relation}),
    do: relation
  defp relation!(op, type, name, nil),
    do: raise(ArgumentError, "cannot #{op} #{type} `#{name}` (only embeds, belongs_to, has_one and has_many associations are supported)")
  defp relation!(op, type, name, {other, _}) when other in @relations,
    do: raise(ArgumentError, "expected `#{name}` to be an #{type} in `#{op}_#{type}`, got: `#{other}`")
  defp relation!(op, type, name, schema_type),
    do: raise(ArgumentError, "expected `#{name}` to be an #{type} in `#{op}_#{type}`, got: `#{inspect schema_type}`")

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
    params of `changeset2` in case of a conflict. If both changesets have their
    `:params` fields set to `nil`, the resulting changeset will have its params
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

      iex> changeset1 = cast(%{title: "Title"}, %Post{body: "Body"}, ~w(title), ~w(body))
      iex> changeset2 = cast(%{title: "New title"}, %Post{}, ~w(title), ~w())
      iex> merge(changeset1, changeset2)
      ** (ArgumentError) different models when merging changesets

  """
  @spec merge(t, t) :: t | no_return
  def merge(changeset1, changeset2)

  def merge(%Changeset{model: model} = cs1, %Changeset{model: model} = cs2) do
    new_repo        = merge_identical(cs1.repo, cs2.repo, "repos")
    new_action      = merge_identical(cs1.action, cs2.action, "actions")
    new_filters     = Map.merge(cs1.filters, cs2.filters)
    new_validations = cs1.validations ++ cs2.validations
    new_constraints = cs1.constraints ++ cs2.constraints

    cast_merge %{cs1 | repo: new_repo, filters: new_filters,
                       action: new_action, validations: new_validations,
                       constraints: new_constraints}, cs2
  end

  def merge(%Changeset{}, %Changeset{}) do
    raise ArgumentError, message: "different models when merging changesets"
  end

  defp cast_merge(cs1, cs2) do
    new_params   = (cs1.params || cs2.params) && Map.merge(cs1.params || %{}, cs2.params || %{})
    new_changes  = Map.merge(cs1.changes, cs2.changes)
    new_errors   = Enum.uniq(cs1.errors ++ cs2.errors)
    new_required = Enum.uniq(cs1.required ++ cs2.required)
    new_types    = cs1.types || cs2.types
    new_valid?   = cs1.valid? and cs2.valid?

    %{cs1 | params: new_params, valid?: new_valid?, errors: new_errors, types: new_types,
            changes: new_changes, required: new_required}
  end

  defp merge_identical(object, nil, _thing), do: object
  defp merge_identical(nil, object, _thing), do: object
  defp merge_identical(object, object, _thing), do: object
  defp merge_identical(lhs, rhs, thing) do
    raise ArgumentError, "different #{thing} (`#{inspect lhs}` and " <>
                         "`#{inspect rhs}`) when merging changesets"
  end

  @doc """
  Fetches the given field from changes or from the model.

  While `fetch_change/2` only looks at the current `changes`
  to retrieve a value, this function looks at the changes and
  then falls back on the model, finally returning `:error` if
  no value is available.

  For relations this functions will return the models with changes applied,
  as if they were taken from model.
  To retrieve raw changesets, please use `fetch_change/2`.

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
  def fetch_field(%Changeset{changes: changes, model: model, types: types}, key) do
    case Map.fetch(changes, key) do
      {:ok, value} ->
        {:changes, change_as_field(types, key, value)}
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

  For relations this functions will return the models with changes applied,
  as if they were taken from model.
  To retrieve raw changesets, please use `get_change/3`.

      iex> post = %Post{title: "A title", body: "My body is a cage"}
      iex> changeset = change(post, %{title: "A new title"})
      iex> get_field(changeset, :title)
      "A new title"
      iex> get_field(changeset, :not_a_field, "Told you, not a field!")
      "Told you, not a field!"

  """
  @spec get_field(t, atom, term) :: term
  def get_field(%Changeset{changes: changes, model: model, types: types}, key, default \\ nil) do
    case Map.fetch(changes, key) do
      {:ok, value} ->
        change_as_field(types, key, value)
      :error ->
        case Map.fetch(model, key) do
          {:ok, value} -> value
          :error       -> default
        end
    end
  end

  defp change_as_field(types, key, value) do
    case Map.get(types, key) do
      {tag, relation} when tag in @relations ->
         Relation.apply_changes(relation, value)
      _other ->
        value
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
  @spec put_change(t, atom, term) :: t | no_return
  def put_change(%Changeset{types: nil}, _key, _value) do
    raise ArgumentError, "changeset does not have types information"
  end

  def put_change(%Changeset{types: types} = changeset, key, value) do
    type = Map.get(types, key)
    {changes, errors, valid?} =
      put_change(changeset.model, changeset.changes, changeset.errors,
                 changeset.valid?, key, value, type)
    %{changeset | changes: changes, errors: errors, valid?: valid?}
  end

  defp put_change(_model, _changes, _errors, _valid?, _key, _value, {tag, _})
      when tag in @relations do
    raise "changing #{tag}s with change/2 or put_change/3 is not supported, " <>
          "please use put_#{tag}/4 instead"
  end

  defp put_change(model, changes, errors, valid?, key, value, _type) do
    cond do
      Map.get(model, key) != value ->
        {Map.put(changes, key, value), errors, valid?}
      Map.has_key?(changes, key) ->
        {Map.delete(changes, key), errors, valid?}
      true ->
        {changes, errors, valid?}
    end
  end

  @doc """
  Puts the given association as change in the changeset.

  The association may either be the association struct or a
  changeset for the given association.

  If the association has no changes, it will be skipped.
  If the association is invalid, the changeset will be marked
  as invalid. If the given value is not an association, it
  will raise.
  """
  def put_assoc(changeset, name, value, opts \\ []) do
    put_relation(:assoc, changeset, name, value, opts)
  end

  @doc """
  Puts the given embed as change in the changeset.

  The embed may either be the embed struct or a changeset
  for the given embed.

  If the embed has no changes, it will be skipped.
  If the embed is invalid, the changeset will be marked
  as invalid. If the given value is not an embed, it
  will raise.
  """
  def put_embed(changeset, name, value, opts \\ []) do
    put_relation(:embed, changeset, name, value, opts)
  end

  defp put_relation(_type, %Changeset{types: nil}, _name, _value, _opts) do
    raise ArgumentError, "changeset does not have types information"
  end

  defp put_relation(type, changeset, name, value, _opts) do
    %{model: model, types: types, changes: changes} = changeset

    relation = relation!(:put, type, name, Map.get(types, name))
    current  = Relation.load!(model, Map.get(model, name))

    case Relation.change(relation, value, current) do
      {:ok, _, _, true} ->
        changeset
      {:ok, change, relation_valid?, false} ->
        %{changeset | changes: Map.put(changes, name, change),
                      valid?: changeset.valid? && relation_valid?}
      :error ->
        %{changeset | errors: [{name, "is invalid"} | changeset.errors], valid?: false}
    end
  end

  @doc """
  Forces a change on the given `key` with `value`.

  If the change is already present, it is overridden with
  the new value.

  ## Examples

      iex> changeset = change(%Post{author: "bar"}, %{title: "foo"})
      iex> changeset = force_change(changeset, :title, "bar")
      iex> changeset.changes
      %{title: "bar"}

      iex> changeset = force_change(changeset, :author, "bar")
      iex> changeset.changes
      %{title: "bar", author: "bar"}

  """
  @spec force_change(t, atom, term) :: t | no_return
  def force_change(%Changeset{types: nil}, _key, _value) do
    raise ArgumentError, "changeset does not have types information"
  end

  def force_change(%Changeset{types: types} = changeset, key, value) do
    case Map.get(types, key) do
      {tag, _} when tag in @relations ->
        raise "changing #{tag}s with force_change/3 is not supported, " <>
              "please use put_#{tag}/4 instead"
      _ ->
        update_in changeset.changes, &Map.put(&1, key, value)
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
  def delete_change(%Changeset{} = changeset, key) when is_atom(key) do
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
  @spec apply_changes(t) :: Ecto.Schema.t
  def apply_changes(%Changeset{changes: changes, model: model}) when changes == %{} do
    model
  end

  def apply_changes(%Changeset{changes: changes, model: model, types: types}) do
    Enum.reduce(changes, model, fn {key, value}, acc ->
      case Map.fetch(types, key) do
        {:ok, {tag, relation}} when tag in @relations ->
          Map.put(acc, key, Relation.apply_changes(relation, value))
        {:ok, _} ->
          Map.put(acc, key, value)
        :error ->
          acc
      end
    end)
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
  def add_error(%{errors: errors} = changeset, key, message) when is_binary(message) do
    %{changeset | errors: [{key, message}|errors], valid?: false}
  end

  def add_error(%{errors: errors} = changeset, key, {message, opts} = error)
      when is_binary(message) and is_list(opts) do
    %{changeset | errors: [{key, error}|errors], valid?: false}
  end

  @doc """
  Validates the given `field` change.

  It invokes the `validator` function to perform the validation
  only if a change for the given `field` exists and the change
  value is not `nil`. The function must return a list of errors
  (with an empty list meaning no errors).

  In case there's at least one error, the list of errors will be appended to the
  `:errors` field of the changeset and the `:valid?` flag will be set to
  `false`.

  ## Examples

      iex> changeset = change(%Post{}, %{title: "foo"})
      iex> changeset = validate_change changeset, :title, fn
      ...>   # Value must not be "foo"!
      ...>   :title, "foo" -> [title: "is foo"]
      ...>   :title, _     -> []
      ...> end
      iex> changeset.errors
      [title: "is_foo"]

  """
  @spec validate_change(t, atom, (atom, term -> [error])) :: t
  def validate_change(changeset, field, validator) when is_atom(field) do
    %{changes: changes, errors: errors} = changeset

    value = Map.get(changes, field)
    new   = if is_nil(value), do: [], else: validator.(field, value)

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
  @spec validate_change(t, atom, term, (atom, term -> [error])) :: t
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
  @spec validate_format(t, atom, Regex.t, Keyword.t) :: t
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
  @spec validate_inclusion(t, atom, Enum.t, Keyword.t) :: t
  def validate_inclusion(changeset, field, data, opts \\ []) do
    validate_change changeset, field, {:inclusion, data}, fn _, value ->
      if value in data, do: [], else: [{field, message(opts, "is invalid")}]
    end
  end

  @doc ~S"""
  Validates a change, of type enum, is a subset of the given enumerable. Like
  validate_inclusion/4 for lists.

  ## Options

    * `:message` - the message on failure, defaults to "has an invalid entry"

  ## Examples

      validate_subset(changeset, :pets, ["cat", "dog", "parrot"])
      validate_subset(changeset, :lottery_numbers, 0..99)

  """
  @spec validate_subset(t, atom, Enum.t, Keyword.t) :: t
  def validate_subset(changeset, field, data, opts \\ []) do
    validate_change changeset, field, {:subset, data}, fn _, value ->
      case Enum.any?(value, fn(x) -> not x in data end) do
        true -> [{field, message(opts, "has an invalid entry")}]
        false -> []
      end
    end
  end

  @doc """
  Validates a change is not included in the given enumerable.

  ## Options

    * `:message` - the message on failure, defaults to "is reserved"

  ## Examples

      validate_exclusion(changeset, :name, ~w(admin superadmin))

  """
  @spec validate_exclusion(t, atom, Enum.t, Keyword.t) :: t
  def validate_exclusion(changeset, field, data, opts \\ []) do
    validate_change changeset, field, {:exclusion, data}, fn _, value ->
      if value in data, do: [{field, message(opts, "is reserved")}], else: []
    end
  end

  @doc """
  Validates a change is a string or list of the given length.

  ## Options

    * `:is` - the length must be exactly this value
    * `:min` - the length must be greater than or equal to this value
    * `:max` - the length must be less than or equal to this value
    * `:message` - the message on failure, depending on the validation, is one of:
      * for strings:
        * "should be %{count} character(s)"
        * "should be at least %{count} character(s)"
        * "should be at most %{count} character(s)"
      * for lists:
        * "should have %{count} item(s)"
        * "should have at least %{count} item(s)"
        * "should have at most %{count} item(s)"

  ## Examples

      validate_length(changeset, :title, min: 3)
      validate_length(changeset, :title, max: 100)
      validate_length(changeset, :title, min: 3, max: 100)
      validate_length(changeset, :code, is: 9)
      validate_length(changeset, :topics, is: 2)

  """
  @spec validate_length(t, atom, Keyword.t) :: t
  def validate_length(changeset, field, opts) when is_list(opts) do
    validate_change changeset, field, {:length, opts}, fn
      _, value ->
        {type, length} = case value do
          value when is_binary(value) ->
            {:string, String.length(value)}
          value when is_list(value) ->
            {:list, length(value)}
        end

        error = ((is = opts[:is]) && wrong_length(type, length, is, opts)) ||
                ((min = opts[:min]) && too_short(type, length, min, opts)) ||
                ((max = opts[:max]) && too_long(type, length, max, opts))

        if error, do: [{field, error}], else: []
    end
  end

  defp wrong_length(_type, value, value, _opts), do: nil
  defp wrong_length(:string, _length, value, opts), do:
    {message(opts, "should be %{count} character(s)"), count: value}
  defp wrong_length(:list, _length, value, opts), do:
    {message(opts, "should have %{count} item(s)"), count: value}

  defp too_short(_type, length, value, _opts) when length >= value, do: nil
  defp too_short(:string, _length, value, opts), do:
    {message(opts, "should be at least %{count} character(s)"), count: value}
  defp too_short(:list, _length, value, opts), do:
    {message(opts, "should have at least %{count} item(s)"), count: value}

  defp too_long(_type, length, value, _opts) when length <= value, do: nil
  defp too_long(:string, _length, value, opts), do:
    {message(opts, "should be at most %{count} character(s)"), count: value}
  defp too_long(:list, _length, value, opts), do:
    {message(opts, "should have at most %{count} item(s)"), count: value}

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
  @spec validate_number(t, atom, Keyword.t) :: t | no_return
  def validate_number(changeset, field, opts) do
    validate_change changeset, field, {:number, opts}, fn
      field, value ->
        {message, opts} = Keyword.pop(opts, :message)
        Enum.find_value opts, [], fn {spec_key, target_value} ->
          case Map.fetch(@number_validators, spec_key) do
            {:ok, {spec_function, default_message}} ->
              validate_number(field, value, message || default_message,
                              spec_key, spec_function, target_value)
            :error ->
              raise ArgumentError, "unknown option #{inspect spec_key} given to validate_number/3"
          end
        end
    end
  end

  defp validate_number(field, %Decimal{} = value, message, spec_key, _spec_function, target_value) do
    result = Decimal.compare(value, target_value)
    case decimal_compare(result, spec_key) do
      true  -> nil
      false -> [{field, {message, count: target_value}}]
    end
  end

  defp validate_number(field, value, message, _spec_key, spec_function, target_value) do
    case apply(spec_function, [value, target_value]) do
      true  -> nil
      false -> [{field, {message, count: target_value}}]
    end
  end

  defp decimal_compare(result, :less_than) do
    Decimal.equal?(result, Decimal.new(-1))
  end

  defp decimal_compare(result, :greater_than) do
    Decimal.equal?(result, Decimal.new(1))
  end

  defp decimal_compare(result, :equal_to) do
    Decimal.equal?(result, Decimal.new(0))
  end

  defp decimal_compare(result, :less_than_or_equal_to) do
    decimal_compare(result, :less_than) or decimal_compare(result, :equal_to)
  end

  defp decimal_compare(result, :greater_than_or_equal_to) do
    decimal_compare(result, :greater_than) or decimal_compare(result, :equal_to)
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
      validate_confirmation(changeset, :password, message: "does not match password")

      cast(model, params, ~w(password), ~w())
      |> validate_confirmation(:password, message: "does not match password")

  """
  @spec validate_confirmation(t, atom, Keyword.t) :: t
  def validate_confirmation(changeset, field, opts \\ []) do
    validate_change changeset, field, {:confirmation, opts}, fn _, _ ->
      param = Atom.to_string(field)
      error_param = "#{param}_confirmation"
      error_field = String.to_atom(error_param)
      value = Map.get(changeset.params, param)

      case Map.fetch(changeset.params, error_param) do
        {:ok, ^value} -> []
        {:ok, _}      -> [{error_field, message(opts, "does not match confirmation")}]
        :error        -> []
      end
    end
  end

  defp message(opts, default) do
    Keyword.get(opts, :message, default)
  end

  ## Optimistic lock

  @doc ~S"""
  Applies optimistic locking to the changeset.

  [Optimistic
  locking](http://en.wikipedia.org/wiki/Optimistic_concurrency_control) (or
  *optimistic concurrency control*) is a technique that allows concurrent edits
  on a single record. While pessimistic locking works by locking a resource for
  an entire transaction, optimistic locking only checks if the resource changed
  before updating it.

  This is done by regularly fetching the record from the database, then checking
  whether another user has made changes to the record *only when updating the
  record*. This behaviour is ideal in situations where the chances of concurrent
  updates to the same record are low; if they're not, pessimistic locking or
  other concurrency patterns may be more suited.

  ## Usage

  Optimistic locking works by keeping a "version" counter for each record; this
  counter gets incremented each time a modification is made to a record. Hence,
  in order to use optimistic locking, a field must exist in your schema for
  versioning purpose. Such field is usually an integer but other types are
  supported.

  ## Examples

  Assuming we have a `Post` schema (stored in the `posts` table), the first step
  is to add a version column to the `posts` table:

      alter table(:posts) do
        add :lock_version, :integer, default: 1
      end

  The column name is arbitrary and doesn't need to be `:lock_version`. Now add
  a field to the schema too:

      defmodule Post do
        use Ecto.Schema

        schema "posts" do
          field :title, :string
          field :lock_version, :integer, default: 1
        end

        def changeset(:update, struct, params \\ :empty) do
          struct
          |> Ecto.Changeset.cast(struct, params, ~w(:title))
          |> Ecto.Changeset.optimistic_lock(:lock_version)
        end
      end

  Now let's take optimistic locking for a spin:

      iex> post = Repo.insert!(%Post{title: "foo"})
      %Post{id: 1, title: "foo", lock_version: 1}
      iex> valid_change = Post.changeset(:update, post, %{title: "bar"})
      iex> stale_change = Post.changeset(:update, post, %{title: "baz"})
      iex> Repo.update!(valid_change)
      %Post{id: 1, title: "bar", lock_version: 2}
      iex> Repo.update!(stale_change)
      ** (Ecto.StaleEntryError) attempted to update a stale model:

      %Post{id: 1, title: "baz", lock_version: 1}

  When a conflict happens (a record which has been previously fetched is
  being updated, but that same record has been modified since it was
  fetched), an `Ecto.StaleEntryError` exception is raised.

  Optimistic locking also works with delete operations. Just call the
  `optimistic_lock` function with the model before delete:

      iex> changeset = Ecto.Changeset.optimistic_lock(post, :lock_version)
      iex> Repo.delete(changeset)

  Finally, keep in `optimistic_lock/3` by default assumes the field
  being used as a lock is an integer. If you want to use another type,
  you need to pass the third argument customizing how the next value
  is generated:

      iex> Ecto.Changeset.optimistic_lock(post, :lock_uuid, fn _ -> Ecto.UUID.generate end)

  """
  @spec optimistic_lock(Ecto.Schema.t | t, atom, (integer -> integer)) :: t | no_return
  def optimistic_lock(model_or_changeset, field, incrementer \\ &(&1 + 1)) do
    changeset = change(model_or_changeset, %{})
    current = Map.fetch!(changeset.model, field)
    update_in(changeset.filters, &Map.put(&1, field, current))
    |> force_change(field, incrementer.(current))
  end

  @doc """
  Provides a function to run before emitting changes to the repository.

  Such function receives the changeset and must return a changeset,
  allowing developers to do final adjustments to the changeset or to
  issue data consistency commands.

  The given function is guaranteed to run inside the same transaction
  as the changeset operation for databases that do support transactions.
  """
  @spec prepare_changes(t, (t -> t)) :: t
  def prepare_changes(changeset, function) when is_function(function, 1) do
    update_in changeset.prepare, &[function|&1]
  end

  ## Constraints

  @doc """
  Checks for a unique constraint in the given field.

  The unique constraint works by relying on the database to check
  if the unique constraint has been violated or not and, if so,
  Ecto converts it into a changeset error.

  In order to use the uniqueness constraint the first step is
  to define the unique index in a migration:

      create unique_index(:users, [:email])

  Now that a constraint exists, when modifying users, we could
  annotate the changeset with unique constraint so Ecto knows
  how to convert it into an error message:

      cast(user, params, ~w(email), ~w())
      |> unique_constraint(:email)

  Now, when invoking `Repo.insert/2` or `Repo.update/2`, if the
  email already exists, it will be converted into an error and
  `{:error, changeset}` returned by the repository. Note that the error
  will occur only after hitting the database so it will not be visible
  until all other validations pass.

  ## Options

    * `:message` - the message in case the constraint check fails,
      defaults to "has already been taken"
    * `:name` - the constraint name. By default, the constraint
      name is inflected from the table + field. May be required
      explicitly for complex cases

  ## Complex constraints

  Because the constraint logic is in the database, we can leverage
  all the database functionality when defining them. For example,
  let's suppose the e-mails are scoped by company id. We would write
  in a migration:

      create unique_index(:users, [:email, :company_id])

  Because such indexes have usually more complex names, we need
  to explicitly tell the changeset which constraint name to use:

      cast(user, params, ~w(email), ~w())
      |> unique_constraint(:email, name: :posts_email_company_id_index)

  Alternatively, you can give both `unique_index` and `unique_constraint`
  a name:

      # In the migration
      create unique_index(:users, [:email, :company_id], name: :posts_special_email_index)

      # In the model
      cast(user, params, ~w(email), ~w())
      |> unique_constraint(:email, name: :posts_email_company_id_index)

  ## Case sensitivity

  Unfortunately, different databases provide different guarantees
  when it comes to case-sensitiveness. For example, in MySQL, comparisons
  are case-insensitive by default. In Postgres, users can define case
  insensitive column by using the `:citext` type/extension.

  If for some reason your database does not support case insensitive columns,
  you can explicitly downcase values before inserting/updating them:

      cast(model, params, ~w(email), ~w())
      |> update_change(:email, &String.downcase/1)
      |> unique_constraint(:email)

  """
  @spec unique_constraint(t, atom, Keyword.t) :: t
  def unique_constraint(changeset, field, opts \\ []) do
    constraint = opts[:name] || "#{get_source(changeset)}_#{field}_index"
    message    = opts[:message] || "has already been taken"
    add_constraint(changeset, :unique, to_string(constraint), field, message)
  end

  @doc """
  Checks for foreign key constraint in the given field.

  The foreign key constraint works by relying on the database to
  check if the associated model exists or not. This is useful to
  guarantee that a child will only be created if the parent exists
  in the database too.

  In order to use the foreign key constraint the first step is
  to define the foreign key in a migration. This is often done
  with references. For example, imagine you are creating a
  comments table that belongs to posts. One would have:

      create table(:comments) do
        add :post_id, references(:posts)
      end

  By default, Ecto will generate a foreign key constraint with
  name "comments_post_id_fkey" (the name is configurable).

  Now that a constraint exists, when creating comments, we could
  annotate the changeset with foreign key constraint so Ecto knows
  how to convert it into an error message:

      cast(comment, params, ~w(post_id), ~w())
      |> foreign_key_constraint(:post_id)

  Now, when invoking `Repo.insert/2` or `Repo.update/2`, if the
  associated post does not exist, it will be converted into an
  error and `{:error, changeset}` returned by the repository.

  ## Options

    * `:message` - the message in case the constraint check fails,
      defaults to "does not exist"
    * `:name` - the constraint name. By default, the constraint
      name is inflected from the table + field. May be required
      explicitly for complex cases

  """
  @spec foreign_key_constraint(t, atom, Keyword.t) :: t
  def foreign_key_constraint(changeset, field, opts \\ []) do
    constraint = opts[:name] || "#{get_source(changeset)}_#{field}_fkey"
    message    = opts[:message] || "does not exist"
    add_constraint(changeset, :foreign_key, to_string(constraint), field, message)
  end

  @doc """
  Checks the associated model exists.

  This is similar to `foreign_key_constraint/3` except that the
  field is inflected from the association definition. This is useful
  to guarantee that a child will only be created if the parent exists
  in the database too. Therefore, it only applies to `belongs_to`
  associations.

  As the name says, a constraint is required in the database for
  this function to work. Such constraint is often added as a
  reference to the child table:

      create table(:comments) do
        add :post_id, references(:posts)
      end

  Now, when inserting a comment, it is possible to forbid any
  comment to be added if the associated post does not exist:

      comment
      |> Ecto.Changeset.cast(params, ~w(post_id))
      |> Ecto.Changeset.assoc_constraint(:post)
      |> Repo.insert

  ## Options

    * `:message` - the message in case the constraint check fails,
      defaults to "does not exist"
    * `:name` - the constraint name. By default, the constraint
      name is inflected from the table + association field.
      May be required explicitly for complex cases
  """
  @spec assoc_constraint(t, atom, Keyword.t) :: t | no_return
  def assoc_constraint(changeset, assoc, opts \\ []) do
    constraint = opts[:name] ||
      (case get_assoc(changeset, assoc) do
        %Ecto.Association.BelongsTo{owner_key: owner_key} ->
          "#{get_source(changeset)}_#{owner_key}_fkey"
        other ->
          raise ArgumentError,
            "assoc_constraint can only be added to belongs to associations, got: #{inspect other}"
      end)

    message = opts[:message] || "does not exist"
    add_constraint(changeset, :foreign_key, to_string(constraint), assoc, message)
  end

  @doc """
  Checks the associated model does not exist.

  This is similar to `foreign_key_constraint/3` except that the
  field is inflected from the association definition. This is useful
  to guarantee that parent can only be deleted (or have its primary
  key changed) if no child exists in the database. Therefore, it only
  applies to `has_*` associations.

  As the name says, a constraint is required in the database for
  this function to work. Such constraint is often added as a
  reference to the child table:

      create table(:comments) do
        add :post_id, references(:posts)
      end

  Now, when deleting the post, it is possible to forbid any post to
  be deleted if they still have comments attached to it:

      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.no_assoc_constraint(:comments)
      |> Repo.delete

  ## Options

    * `:message` - the message in case the constraint check fails,
      defaults to "is still associated to this entry" (for has_one)
      and "are still associated to this entry" (for has_many)
    * `:name` - the constraint name. By default, the constraint
      name is inflected from the association table + association
      field. May be required explicitly for complex cases
  """
  @spec no_assoc_constraint(t, atom, Keyword.t) :: t | no_return
  def no_assoc_constraint(changeset, assoc, opts \\ []) do
    {constraint, message} =
      (case get_assoc(changeset, assoc) do
        %Ecto.Association.Has{cardinality: cardinality,
                              related_key: related_key, related: related} ->
          {opts[:name] || "#{related.__schema__(:source)}_#{related_key}_fkey",
           opts[:message] || no_assoc_message(cardinality)}
        other ->
          raise ArgumentError,
            "no_assoc_constraint can only be added to has one/many associations, got: #{inspect other}"
      end)

    add_constraint(changeset, :foreign_key, to_string(constraint), assoc, message)
  end

  @doc """
  Checks for a exclude constraint in the given field.

  The exclude constraint works by relying on the database to check
  if the exclude constraint has been violated or not and, if so,
  Ecto converts it into a changeset error.

  ## Options

    * `:message` - the message in case the constraint check fails,
      defaults to "violates an exclusion constraint"
    * `:name` - the constraint name. By default, the constraint
      name is inflected from the table + field. May be required
      explicitly for complex cases

  """
  def exclude_constraint(changeset, field, opts \\ []) do
    constraint = opts[:name] || "#{get_source(changeset)}_#{field}_exclusion"
    message    = opts[:message] || "violates an exclusion constraint"
    add_constraint(changeset, :exclude, to_string(constraint), field, message)
  end

  defp no_assoc_message(:one), do: "is still associated to this entry"
  defp no_assoc_message(:many), do: "are still associated to this entry"

  defp add_constraint(changeset, type, constraint, field, message)
       when is_binary(constraint) and is_atom(field) and is_binary(message) do
    update_in changeset.constraints, &[%{type: type, constraint: constraint,
                                         field: field, message: message}|&1]
  end

  defp get_source(%{model: %{__meta__: %{source: {_prefix, source}}}}) when is_binary(source),
    do: source
  defp get_source(%{model: model}), do:
    raise(ArgumentError, "cannot add constraint to changeset because it does not have a source, got: #{inspect model}")

  defp get_assoc(%{model: %{__struct__: model}}, assoc) do
    model.__schema__(:association, assoc) ||
      raise(ArgumentError, "cannot add constraint to changeset because association `#{assoc}` does not exist")
  end

  @doc """
  Traverses changeset errors and applies function to error messages.

  This function is particularly useful when associations and embeds
  are cast in the changeset as it will traverse all associations and
  embeds and place all errors in a series of nested maps.

  A changeset is supplied along with a function to apply to each
  error message as the changeset is traversed. The error message
  function receives a single argument matching either:

    * `{message, opts}` - The string error message and options,
      for example `{"should be at least %{count} characters", [count: 3]}`
    * `message` - The string error message

  ## Examples

      iex> traverse_errors(changeset, fn
        {msg, opts} -> String.replace(msg, "%{count}", to_string(opts[:count]))
        msg -> msg
      end)
      %{title: "should be at least 3 characters"}
  """
  @spec traverse_errors(t, (error_message -> String.t)) :: %{atom => String.t}
  def traverse_errors(%Changeset{errors: errors, changes: changes, types: types}, msg_func) do
    errors
    |> Enum.reverse()
    |> merge_error_keys(msg_func)
    |> merge_related_keys(changes, types, msg_func)
  end

  defp merge_error_keys(errors, msg_func) do
    Enum.reduce(errors, %{}, fn({key, val}, acc) ->
      val = msg_func.(val)
      Map.update(acc, key, [val], &[val|&1])
    end)
  end

  defp merge_related_keys(map, changes, types, msg_func) do
    Enum.reduce types, map, fn
      {field, {tag, %{cardinality: :many}}}, acc when tag in @relations ->
        if changesets = Map.get(changes, field) do
          Map.put(acc, field, Enum.map(changesets, &traverse_errors(&1, msg_func)))
        else
          acc
        end
      {field, {tag, %{cardinality: :one}}}, acc when tag in @relations ->
        if changeset = Map.get(changes, field) do
          Map.put(acc, field, traverse_errors(changeset, msg_func))
        else
          acc
        end
      {_, _}, acc ->
        acc
    end
  end
end

defimpl Inspect, for: Ecto.Changeset do
  import Inspect.Algebra

  def inspect(changeset, opts) do
    list = for attr <- [:action, :changes, :errors, :model, :valid?] do
      {attr, Map.get(changeset, attr)}
    end

    surround_many("#Ecto.Changeset<", list, ">", opts, fn
      {:action, action}, opts   -> concat("action: ", to_doc(action, opts))
      {:changes, changes}, opts -> concat("changes: ", to_doc(changes, opts))
      {:errors, errors}, opts   -> concat("errors: ", to_doc(errors, opts))
      {:model, model}, _opts    -> concat("model: ", to_struct(model))
      {:valid?, valid?}, opts   -> concat("valid?: ", to_doc(valid?, opts))
    end)
  end

  defp to_struct(nil), do: "nil"
  defp to_struct(%{__struct__: struct}), do: "#" <> Kernel.inspect(struct) <> "<>"
end
