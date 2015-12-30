import Ecto.Query, only: [from: 2, join: 4, distinct: 3, select: 3]

defmodule Ecto.Association.NotLoaded do
  @moduledoc """
  Struct returned by one to one associations when they are not loaded.

  The fields are:

    * `__field__` - the association field in `owner`
    * `__owner__` - the schema that owns the association
    * `__cardinality__` - the cardinality of the association

  """
  defstruct [:__field__, :__owner__, :__cardinality__]

  defimpl Inspect do
    def inspect(not_loaded, _opts) do
      msg = "association #{inspect not_loaded.__field__} is not loaded"
      ~s(#Ecto.Association.NotLoaded<#{msg}>)
    end
  end
end

defmodule Ecto.Association do
  @moduledoc false

  @type t :: %{__struct__: atom,
               cardinality: :one | :many,
               relationship: :parent | :child,
               owner: atom,
               owner_key: atom,
               field: atom}

  @doc """
  Builds the association struct.

  The struct must be defined in the module that implements the
  callback and it must contain at least the following keys:

    * `:cardinality` - tells if the association is one to one
      or one/many to many

    * `:field` - tells the field in the owner struct where the
      association should be stored

    * `:owner` - the owner module of the association

    * `:owner_key` - the key in the owner with the association value

    * `:relationship` - if the relationship to the specified entity is
      of a child or a parent

  """
  @callback struct(module, field :: atom, opts :: Keyword.t) :: t

  @doc """
  Builds a struct for the given association.

  The struct to build from is given as argument in case default values
  should be set in the struct.

  Invoked by `Ecto.build_assoc/3`.
  """
  @callback build(t, Ecto.Schema.t, %{atom => term} | [Keyword.t]) :: Ecto.Schema.t

  @doc """
  Returns an association join query.

  This callback receives the association struct and it must return
  a query that retrieves all associated entries using joins up to
  the owner association.

  For example, a `has_many :comments` inside a `Post` module would
  return:

      from c in Comment, join: p in Post, on: c.post_id == p.id

  Note all the logic must be expressed inside joins, as fields like
  `where` and `order_by` won't be used by the caller.

  This callback is invoked when `join: assoc(p, :comments)` is used
  inside queries.
  """
  @callback joins_query(t) :: Ecto.Query.t

  @doc """
  Returns the association query on top of the given query.

  If the query is `nil`, the association target must be used.

  This callback receives the association struct and it must return
  a query that retrieves all associated entries with the given
  values for the owner key.

  This callback is used by `Ecto.assoc/2` and when preloading.
  """
  @callback assoc_query(t, Ecto.Query.t | nil, values :: [term]) :: Ecto.Query.t

  @doc """
  Returns information used by the preloader.
  """
  @callback preload_info(t) ::
              {:assoc, t, {integer, atom}} | {:through, t, [atom]}

  @doc """
  Performs the repository change on the association.

  Receives the parent changeset, the currente changesets
  and the repository action optoins. Must returns the
  persisted struct (or nil) or the changeset error.
  """
  @callback on_repo_change(t, parent :: Ecto.Changeset.t, changeset :: Ecto.Changeset.t, Keyword.t) ::
            {:ok, Ecto.Schema.t | nil} | {:error, Ecto.Changeset.t}

  @doc """
  Retrieves the association from the given schema.
  """
  def association_from_schema!(schema, assoc) do
    schema.__schema__(:association, assoc) ||
      raise ArgumentError, "schema #{inspect schema} does not have association #{inspect assoc}"
  end

  @doc """
  Returns the association key for the given module with the given suffix.

  ## Examples

      iex> Ecto.Association.association_key(Hello.World, :id)
      :world_id

      iex> Ecto.Association.association_key(Hello.HTTP, :id)
      :http_id

      iex> Ecto.Association.association_key(Hello.HTTPServer, :id)
      :http_server_id

  """
  def association_key(module, suffix) do
    prefix = module |> Module.split |> List.last |> Macro.underscore
    :"#{prefix}_#{suffix}"
  end

  @doc """
  Retrieves related module from queryable.

  ## Examples

      iex> Ecto.Association.related_from_query({"custom_source", Model})
      Model

      iex> Ecto.Association.related_from_query(Model)
      Model

      iex> Ecto.Association.related_from_query("wrong")
      ** (ArgumentError) association queryable must be a schema or {source, schema}, got: "wrong"

  """
  def related_from_query(atom) when is_atom(atom), do: atom
  def related_from_query({source, schema}) when is_binary(source) and is_atom(schema), do: schema
  def related_from_query(queryable) do
    raise ArgumentError, "association queryable must be a schema " <>
      "or {source, schema}, got: #{inspect queryable}"
  end

  @doc """
  Merges source from query into to the given schema.

  In case the query does not have a source, returns
  the schema unchanged.
  """
  def merge_source(schema, query)

  def merge_source(struct, {source, _}) do
    Ecto.put_meta(struct, source: source)
  end

  def merge_source(struct, _query) do
    struct
  end

  @doc """
  Performs the repository action in the related changeset,
  returning `{:ok, model}` or `{:error, changes}`.
  """
  def on_repo_change(%{model: model}, [], _opts) do
    {:ok, model}
  end

  def on_repo_change(changeset, assocs, opts) do
    %{model: model, changes: changes, action: action} = changeset

    {model, changes, valid?} =
      Enum.reduce(assocs, {model, changes, true}, fn {refl, value}, acc ->
        on_repo_change(refl, value, changeset, action, opts, acc)
      end)

    case valid? do
      true  -> {:ok, model}
      false -> {:error, changes}
    end
  end

  defp on_repo_change(%{cardinality: :one, field: field} = meta, nil, parent_changeset,
                      _repo_action, opts, {parent, changes, valid?}) do
    maybe_replace_one!(meta, nil, parent, parent_changeset, opts)
    {Map.put(parent, field, nil), Map.put(changes, field, nil), valid?}
  end

  defp on_repo_change(%{cardinality: :one, field: field, __struct__: mod} = meta,
                      %{action: action} = changeset, parent_changeset,
                      repo_action, opts, {parent, changes, valid?}) do
    check_action!(meta, action, repo_action)
    case mod.on_repo_change(meta, parent_changeset, changeset, opts) do
      {:ok, model} ->
        maybe_replace_one!(meta, model, parent, parent_changeset, opts)
        {Map.put(parent, field, model), Map.put(changes, field, changeset), valid?}
      {:error, changeset} ->
        {parent, Map.put(changes, field, changeset), false}
    end
  end

  defp on_repo_change(%{cardinality: :many, field: field, __struct__: mod} = meta,
                      changesets, parent_changeset, repo_action, opts,
                      {parent, changes, valid?}) do
    {changesets, models, models_valid?} =
      Enum.reduce(changesets, {[], [], true}, fn
        %{action: action} = changeset, {changesets, models, models_valid?} ->
          check_action!(meta, action, repo_action)
          case mod.on_repo_change(meta, parent_changeset, changeset, opts) do
            {:ok, nil} ->
              {[changeset|changesets], models, models_valid?}
            {:ok, model} ->
              {[changeset|changesets], [model | models], models_valid?}
            {:error, changeset} ->
              {[changeset|changesets], models, false}
          end
      end)

    if models_valid? do
      {Map.put(parent, field, Enum.reverse(models)),
       Map.put(changes, field, Enum.reverse(changesets)),
       valid?}
    else
      {parent,
       Map.put(changes, field, Enum.reverse(changesets)),
       false}
    end
  end

  defp check_action!(%{related: schema}, :delete, :insert),
    do: raise(ArgumentError, "got action :delete in changeset for associated #{inspect schema} while inserting")
  defp check_action!(_, _, _), do: :ok

  defp maybe_replace_one!(%{field: field, __struct__: mod} = meta, current, parent,
                          parent_changeset, opts) do
    previous = Map.get(parent, field)
    if replaceable?(previous) and primary_key!(previous) != primary_key!(current) do
      changeset = %{Ecto.Changeset.change(previous) | action: :replace}

      case mod.on_repo_change(meta, parent_changeset, changeset, opts) do
        {:ok, nil} ->
          :ok
        {:error, changeset} ->
          raise Ecto.InvalidChangesetError,
            action: changeset.action, changeset: changeset
      end
    end
  end

  defp maybe_replace_one!(_, _, _, _, _), do: :ok

  defp replaceable?(nil), do: false
  defp replaceable?(%Ecto.Association.NotLoaded{}), do: false
  defp replaceable?(%{__meta__: %{state: :built}}), do: false
  defp replaceable?(_), do: true

  defp primary_key!(nil), do: []
  defp primary_key!(struct), do: Ecto.primary_key!(struct)
end

defmodule Ecto.Association.Has do
  @moduledoc """
  The association struct for `has_one` and `has_many` associations.

  Its fields are:

    * `cardinality` - The association cardinality
    * `field` - The name of the association field on the schema
    * `owner` - The schema where the association was defined
    * `related` - The schema that is associated
    * `owner_key` - The key on the `owner` schema used for the association
    * `related_key` - The key on the `related` schema used for the association
    * `queryable` - The real query to use for querying association
    * `on_delete` - The action taken on associations when schema is deleted
    * `on_replace` - The action taken on associations when schema is replaced
    * `defaults` - Default fields used when building the association
  """

  @behaviour Ecto.Association
  @on_delete_opts [:nothing, :nilify_all, :delete_all]
  @on_replace_opts [:raise, :mark_as_invalid, :delete, :nilify]
  defstruct [:cardinality, :field, :owner, :related, :owner_key, :related_key,
             :queryable, :on_delete, :on_replace, defaults: [], relationship: :child]

  @doc false
  def struct(module, name, opts) do
    ref =
      cond do
        ref = opts[:references] ->
          ref
        primary_key = Module.get_attribute(module, :primary_key) ->
          elem(primary_key, 0)
        true ->
          raise ArgumentError, "need to set :references option for " <>
            "association #{inspect name} when schema has no primary key"
      end

    unless Module.get_attribute(module, :ecto_fields)[ref] do
      raise ArgumentError, "schema does not have the field #{inspect ref} used by " <>
        "association #{inspect name}, please set the :references option accordingly"
    end

    queryable = Keyword.fetch!(opts, :queryable)
    related = Ecto.Association.related_from_query(queryable)

    if opts[:through] do
      raise ArgumentError, "invalid association #{inspect name}. When using the :through " <>
                           "option, the schema should not be passed as second argument"
    end

    on_delete  = Keyword.get(opts, :on_delete, :nothing)
    on_replace = Keyword.get(opts, :on_replace, :raise)

    unless on_delete in @on_delete_opts do
      raise ArgumentError, "invalid :on_delete option for #{inspect name}. " <>
        "The only valid options are: " <>
        Enum.map_join(@on_delete_opts, ", ", &"`#{inspect &1}`")
    end

    unless on_replace in @on_replace_opts do
      raise ArgumentError, "invalid `:on_replace` option for #{inspect name}. " <>
        "The only valid options are: " <>
        Enum.map_join(@on_replace_opts, ", ", &"`#{inspect &1}`")
    end

    %__MODULE__{
      field: name,
      cardinality: Keyword.fetch!(opts, :cardinality),
      owner: module,
      related: related,
      owner_key: ref,
      related_key: opts[:foreign_key] || Ecto.Association.association_key(module, ref),
      queryable: queryable,
      on_delete: on_delete,
      on_replace: on_replace,
      defaults: opts[:defaults] || []
    }
  end

  @doc false
  def build(%{owner_key: owner_key, related_key: related_key} = refl, struct, attributes) do
    refl
    |> build()
    |> struct(attributes)
    |> Map.put(related_key, Map.get(struct, owner_key))
  end

  @doc false
  def joins_query(%{queryable: queryable, related_key: related_key,
                    owner: owner, owner_key: owner_key}) do
    from o in owner,
      join: q in ^queryable,
      on: field(q, ^related_key) == field(o, ^owner_key)
  end

  @doc false
  def assoc_query(%{queryable: queryable, related_key: related_key}, query, values) do
    from x in (query || queryable),
      where: field(x, ^related_key) in ^values
  end

  @doc false
  def preload_info(%{related_key: related_key} = refl) do
    {:assoc, refl, {0, related_key}}
  end

  @doc false
  def on_repo_change(%{on_replace: on_replace} = refl, parent_changeset,
                     %{action: :replace} = changeset, opts) do
    changeset = case on_replace do
      :nilify -> %{changeset | action: :update}
      :delete -> %{changeset | action: :delete}
    end

    case on_repo_change(refl, %{parent_changeset | model: nil}, changeset, opts) do
      {:ok, _} -> {:ok, nil}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def on_repo_change(assoc, parent_changeset, changeset, opts) do
    %{model: parent, repo: repo} = parent_changeset
    %{action: action, changes: changes} = changeset

    {key, value} = parent_key(assoc, parent)
    changeset = update_parent_key(changeset, action, key, value)

    case apply(repo, action, [changeset, opts]) do
      {:ok, _} = ok ->
        if action == :delete, do: {:ok, nil}, else: ok
      {:error, changeset} ->
        original = Map.get(changes, key)
        {:error, update_in(changeset.changes, &Map.put(&1, key, original))}
    end
  end

  defp update_parent_key(changeset, :delete, _key, _value),
    do: changeset
  defp update_parent_key(changeset, _action, key, value),
    do: Ecto.Changeset.put_change(changeset, key, value)

  defp parent_key(%{related_key: related_key}, nil) do
    {related_key, nil}
  end
  defp parent_key(%{owner_key: owner_key, related_key: related_key}, owner) do
    {related_key, Map.get(owner, owner_key)}
  end

  ## Relation callbacks
  @behaviour Ecto.Changeset.Relation

  @doc false
  def build(%{related: related, queryable: queryable, defaults: defaults}) do
    related
    |> struct(defaults)
    |> Ecto.Association.merge_source(queryable)
  end

  ## On delete callbacks

  @doc false
  def delete_all(refl, parent, repo, opts) do
    if query = on_delete_query(refl, parent) do
      repo.delete_all query, opts
    end
  end

  @doc false
  def nilify_all(%{related_key: related_key} = refl, parent, repo, opts) do
    if query = on_delete_query(refl, parent) do
      repo.update_all query, [set: [{related_key, nil}]], opts
    end
  end

  defp on_delete_query(%{owner_key: owner_key, related_key: related_key,
                         queryable: queryable}, parent) do
    if value = Map.get(parent, owner_key) do
      from x in queryable, where: field(x, ^related_key) == ^value
    end
  end
end

defmodule Ecto.Association.HasThrough do
  @moduledoc """
  The association struct for `has_one` and `has_many` through associations.

  Its fields are:

    * `cardinality` - The association cardinality
    * `field` - The name of the association field on the schema
    * `owner` - The schema where the association was defined
    * `owner_key` - The key on the `owner` schema used for the association
    * `through` - The through associations
  """

  alias Ecto.Query.JoinExpr

  @behaviour Ecto.Association
  defstruct [:cardinality, :field, :owner, :owner_key, :through, relationship: :child]

  @doc false
  def struct(module, name, opts) do
    through = Keyword.fetch!(opts, :through)

    refl =
      case through do
        [h,_|_] ->
          Module.get_attribute(module, :ecto_assocs)[h]
        _ ->
          raise ArgumentError, ":through expects a list with at least two entries: " <>
            "the association in the current module and one step through, got: #{inspect through}"
      end

    unless refl do
      raise ArgumentError, "schema does not have the association #{inspect hd(through)} " <>
        "used by association #{inspect name}, please ensure the association exists and " <>
        "is defined before the :through one"
    end

    %__MODULE__{
      field: name,
      cardinality: Keyword.fetch!(opts, :cardinality),
      through: through,
      owner: module,
      owner_key: refl.owner_key,
    }
  end

  @doc false
  def build(%{field: name}, %{__struct__: struct}, _attributes) do
    raise ArgumentError,
      "cannot build through association `#{inspect name}` for #{inspect struct}. " <>
      "Instead build the intermediate steps explicitly."
  end

  @doc false
  def preload_info(%{through: through} = refl) do
    {:through, refl, through}
  end

  def on_repo_change(%{field: name}, _, _, _) do
    raise ArgumentError,
      "cannot insert/update/delete through associations `#{inspect name}` via the repository. " <>
      "Instead build the intermediate steps explicitly."
  end

  @doc false
  def joins_query(%{owner: owner, through: through}) do
    joins_query(owner, through, 0)
  end

  defp joins_query(query, through, counter) do
    Enum.reduce(through, {query, counter}, fn current, {acc, counter} ->
      {join(acc, :inner, [x: counter], assoc(x, ^current)), counter + 1}
    end) |> elem(0)
  end

  @doc false
  def assoc_query(%{owner: owner, through: [h|t]}, query, values) do
    query = query || %Ecto.Query{from: {"join expression", nil}}
    refl  = owner.__schema__(:association, h)

    # Find the position for upcoming joins
    position = length(query.joins) + 1

    # The first association must become a join,
    # so we convert its where (that comes from assoc_query)
    # to a join expression.
    #
    # Note we are being restrictive on the format
    # expected from assoc_query.
    join = assoc_to_join(refl.__struct__.assoc_query(refl, nil, values), position)

    # Add the new join to the query and traverse the remaining
    # joins that will start counting from the added join position.
    query =
      %{query | joins: query.joins ++ [join]}
      |> joins_query(t, position)
      |> Ecto.Query.Planner.prepare_sources()

    # Our source is going to be the last join after
    # traversing them all.
    {joins, [assoc]} = Enum.split(query.joins, -1)

    # Update the mapping and start rewriting expressions
    # to make the last join point to the new from source.
    mapping  = Map.put(%{}, length(joins) + 1, 0)
    assoc_on = rewrite_expr(assoc.on, mapping)

    %{query | wheres: [assoc_on|query.wheres], joins: joins,
              from: merge_from(query.from, assoc.source), sources: nil}
    |> distinct([x], true)
  end

  defp assoc_to_join(%{from: from, wheres: [on], order_bys: [], joins: []}, position) do
    %JoinExpr{ix: position, qual: :inner, source: from,
              on: rewrite_expr(on, %{0 => position}),
              file: on.file, line: on.line}
  end

  defp merge_from({"join expression", _}, assoc_source), do: assoc_source
  defp merge_from(from, _assoc_source), do: from

  defp rewrite_expr(%{expr: expr, params: params} = part, mapping) do
    expr =
      Macro.prewalk expr, fn
        {:&, meta, [ix]} ->
          {:&, meta, [Map.get(mapping, ix, ix)]}
        other ->
          other
      end

    params =
      Enum.map params, fn
        {val, {composite, {ix, field}}} when is_integer(ix) ->
          {val, {composite, {Map.get(mapping, ix, ix), field}}}
        {val, {ix, field}} when is_integer(ix) ->
          {val, {Map.get(mapping, ix, ix), field}}
        val ->
          val
      end

    %{part | expr: expr, params: params}
  end
end

defmodule Ecto.Association.BelongsTo do
  @moduledoc """
  The association struct for a `belongs_to` association.

  Its fields are:

    * `cardinality` - The association cardinality
    * `field` - The name of the association field on the schema
    * `owner` - The schema where the association was defined
    * `owner_key` - The key on the `owner` schema used for the association
    * `related` - The schema that is associated
    * `related_key` - The key on the `related` schema used for the association
    * `queryable` - The real query to use for querying association
    * `defaults` - Default fields used when building the association
  """

  @behaviour Ecto.Association
  @on_replace_opts [:raise, :mark_as_invalid, :delete, :nilify]
  defstruct [:field, :owner, :related, :owner_key, :related_key, :queryable, :on_replace,
             defaults: [], cardinality: :one, relationship: :parent]

  @doc false
  def struct(module, name, opts) do
    ref =
      cond do
        ref = opts[:references] ->
          ref
        primary_key = Module.get_attribute(module, :primary_key) ->
          case elem(primary_key, 0) do
            :id -> :id
            key ->
              IO.puts :stderr,
                "warning: #{inspect module} has a custom primary key and " <>
                "invoked belongs_to(#{inspect name}). To avoid ambiguity, " <>
                "please also specify the :references option in belongs_to " <>
                "with the primary key name of the associated schema, currently " <>
                "it defaults to #{inspect key}\n#{Exception.format_stacktrace}"
              key
          end
        true ->
          :id
      end

    queryable = Keyword.fetch!(opts, :queryable)
    related   = Ecto.Association.related_from_query(queryable)

    unless is_atom(related) do
      raise ArgumentError, "association queryable must be a schema, got: #{inspect related}"
    end

    on_replace = Keyword.get(opts, :on_replace, :raise)

    unless on_replace in @on_replace_opts do
      raise ArgumentError, "invalid `:on_replace` option for #{inspect name}. " <>
        "The only valid options are: " <>
        Enum.map_join(@on_replace_opts, ", ", &"`#{inspect &1}`")
    end

    %__MODULE__{
      field: name,
      owner: module,
      related: related,
      owner_key: Keyword.fetch!(opts, :foreign_key),
      related_key: ref,
      queryable: queryable,
      on_replace: on_replace,
      defaults: opts[:defaults] || []
    }
  end

  @doc false
  def build(refl, _, attributes) do
    refl
    |> build()
    |> struct(attributes)
  end

  @doc false
  def joins_query(%{queryable: queryable, related_key: related_key,
                    owner: owner, owner_key: owner_key}) do
    from o in owner,
      join: q in ^queryable,
      on: field(q, ^related_key) == field(o, ^owner_key)
  end

  @doc false
  def assoc_query(%{queryable: queryable, related_key: related_key}, query, values) do
    from x in (query || queryable),
      where: field(x, ^related_key) in ^values
  end

  @doc false
  def preload_info(%{related_key: related_key} = refl) do
    {:assoc, refl, {0, related_key}}
  end

  @doc false
  def on_repo_change(%{on_replace: :nilify}, _parent_changeset, %{action: :replace}, _opts) do
    {:ok, nil}
  end

  def on_repo_change(%{on_replace: :delete} = refl, parent_changeset,
                     %{action: :replace} = changeset, opts) do
    on_repo_change(refl, parent_changeset, %{changeset | action: :delete}, opts)
  end

  def on_repo_change(_refl, %{repo: repo}, %{action: action} = changeset, opts) do
    case apply(repo, action, [changeset, opts]) do
      {:ok, _} = ok ->
        if action == :delete, do: {:ok, nil}, else: ok
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  ## Relation callbacks
  @behaviour Ecto.Changeset.Relation

  @doc false
  def build(%{related: related, queryable: queryable, defaults: defaults}) do
    related
    |> struct(defaults)
    |> Ecto.Association.merge_source(queryable)
  end
end

defmodule Ecto.Association.ManyToMany do
  @moduledoc """
  The association struct for `many_to_many` associations.

  Its fields are:

    * `cardinality` - The association cardinality
    * `field` - The name of the association field on the schema
    * `owner` - The schema where the association was defined
    * `related` - The schema that is associated
    * `owner_key` - The key on the `owner` schema used for the association
    * `queryable` - The real query to use for querying association
    * `on_delete` - The action taken on associations when schema is deleted
    * `on_replace` - The action taken on associations when schema is replaced
    * `defaults` - Default fields used when building the association
  """

  @behaviour Ecto.Association
  @on_delete_opts [:nothing, :delete_all]
  @on_replace_opts [:raise, :mark_as_invalid, :delete]
  defstruct [:field, :owner, :related, :owner_key, :queryable,
             :on_delete, :on_replace, :join_keys, :join_through,
             defaults: [], relationship: :child, cardinality: :many]

  @doc false
  def struct(module, name, opts) do
    join_through = opts[:join_through]

    if join_through && (is_atom(join_through) or is_binary(join_through)) do
      :ok
    else
      raise ArgumentError,
        "many_to_many #{inspect name} associations require the :join_through option to be " <>
        "given and it must be an atom (representing a schema) or a string (representing a table)"
    end

    join_keys = opts[:join_keys]
    queryable = Keyword.fetch!(opts, :queryable)
    related   = Ecto.Association.related_from_query(queryable)

    {owner_key, join_keys} =
      case join_keys do
        [{join_owner_key, owner_key}, {join_related_key, related_key}]
            when is_atom(join_owner_key) and is_atom(owner_key) and
                 is_atom(join_related_key) and is_atom(related_key) ->
          {owner_key, join_keys}
        nil ->
          {:id, default_join_keys(module, related)}
        _ ->
          raise ArgumentError,
            "many_to_many #{inspect name} expect :join_keys to be a keyword list " <>
            "with two entries, the first being how the join table should reach " <>
            "the current schema and the second how the join table should reach " <>
            "the associated schema. For example: #{inspect default_join_keys(module, related)}"
      end

    unless Module.get_attribute(module, :ecto_fields)[owner_key] do
      raise ArgumentError, "schema does not have the field #{inspect owner_key} used by " <>
        "association #{inspect name}, please set the :join_keys option accordingly"
    end

    on_delete  = Keyword.get(opts, :on_delete, :nothing)
    on_replace = Keyword.get(opts, :on_replace, :raise)

    unless on_delete in @on_delete_opts do
      raise ArgumentError, "invalid :on_delete option for #{inspect name}. " <>
        "The only valid options are: " <>
        Enum.map_join(@on_delete_opts, ", ", &"`#{inspect &1}`")
    end

    unless on_replace in @on_replace_opts do
      raise ArgumentError, "invalid `:on_replace` option for #{inspect name}. " <>
        "The only valid options are: " <>
        Enum.map_join(@on_replace_opts, ", ", &"`#{inspect &1}`")
    end

    %__MODULE__{
      field: name,
      cardinality: Keyword.fetch!(opts, :cardinality),
      owner: module,
      related: related,
      owner_key: owner_key,
      join_keys: join_keys,
      join_through: join_through,
      queryable: queryable,
      on_delete: on_delete,
      on_replace: on_replace,
      defaults: opts[:defaults] || []
    }
  end

  defp default_join_keys(module, related) do
    [{Ecto.Association.association_key(module, :id), :id},
     {Ecto.Association.association_key(related, :id), :id}]
  end

  @doc false
  def joins_query(%{queryable: queryable, owner: owner,
                    join_through: join_through, join_keys: join_keys}) do
    [{join_owner_key, owner_key}, {join_related_key, related_key}] = join_keys
    from o in owner,
      join: j in ^join_through, on: field(j, ^join_owner_key) == field(o, ^owner_key),
      join: q in ^queryable, on: field(j, ^join_related_key) == field(q, ^related_key)
  end

  @doc false
  def assoc_query(%{queryable: queryable} = refl, values) do
    assoc_query(refl, queryable, values)
  end

  @doc false
  def assoc_query(%{join_through: join_through, join_keys: join_keys,
                    queryable: queryable}, query, values) do
    [{join_owner_key, _}, {join_related_key, related_key}] = join_keys
    from q in (query || queryable),
      join: j in ^join_through, on: field(j, ^join_related_key) == field(q, ^related_key),
      where: field(j, ^join_owner_key) in ^values
  end

  @doc false
  def build(refl, _, attributes) do
    refl
    |> build()
    |> struct(attributes)
  end

  @doc false
  def preload_info(%{join_keys: [{join_owner_key, _}, {_, _}]} = refl) do
    {:assoc, refl, {-1, join_owner_key}}
  end

  @doc false
  def on_repo_change(%{on_replace: :delete} = refl, parent_changeset,
                     %{action: :replace}  = changeset, opts) do
    on_repo_change(refl, parent_changeset, %{changeset | action: :delete}, opts)
  end

  def on_repo_change(%{join_keys: join_keys, join_through: join_through},
                     %{repo: repo, model: owner}, %{action: :delete, model: related}, opts) do
    [{join_owner_key, owner_key}, {join_related_key, related_key}] = join_keys

    query =
      from j in join_through,
        where: field(j, ^join_owner_key) == ^field!(:delete, owner, owner_key) and
               field(j, ^join_related_key) == ^field!(:delete, related, related_key)

    repo.delete_all query, opts
    {:ok, nil}
  end

  def on_repo_change(%{field: field, join_through: join_through, join_keys: join_keys},
                     %{repo: repo, model: owner} = parent_changeset,
                     %{action: action} = changeset, opts) do
    case apply(repo, action, [changeset, opts]) do
      {:ok, child} ->
        [{join_owner_key, owner_key}, {join_related_key, related_key}] = join_keys
        if insert_join?(parent_changeset, changeset, field, related_key) do
          data = [{join_owner_key, field!(:insert, owner, owner_key)},
                  {join_related_key, field!(:insert, child, related_key)}]
          insert_join(repo, join_through, data, opts)
        end
        {:ok, child}
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp insert_join?(%{action: :insert}, _, _field, _related_key), do: true
  defp insert_join?(_, %{action: :insert}, _field, _related_key), do: true
  defp insert_join?(%{model: owner}, %{model: related}, field, related_key) do
    current_key = Map.fetch!(related, related_key)
    not Enum.any? Map.fetch!(owner, field), fn child ->
      Map.get(child, related_key) == current_key
    end
  end

  defp insert_join(repo, join_through, data, opts) when is_binary(join_through) do
    repo.insert_all join_through, [data], opts
  end

  defp insert_join(repo, join_through, data, opts) when is_atom(join_through) do
    repo.insert! struct(join_through, data), opts
  end

  defp field!(op, struct, field) do
    Map.get(struct, field) || raise "could not #{op} join entry because `#{field}` is nil in #{inspect struct}"
  end

  ## Relation callbacks
  @behaviour Ecto.Changeset.Relation

  @doc false
  def build(%{related: related, queryable: queryable, defaults: defaults}) do
    related
    |> struct(defaults)
    |> Ecto.Association.merge_source(queryable)
  end

  ## On delete callbacks

  @doc false
  def delete_all(%{join_through: join_through, join_keys: join_keys}, parent, repo, opts) do
    [{join_owner_key, owner_key}, {_, _}] = join_keys
    if value = Map.get(parent, owner_key) do
      query = from j in join_through, where: field(j, ^join_owner_key) == ^value
      repo.delete_all query, opts
    end
  end
end
