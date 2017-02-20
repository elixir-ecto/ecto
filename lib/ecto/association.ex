import Ecto.Query, only: [from: 2, join: 4, distinct: 3]

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
               on_cast: nil | fun,
               cardinality: :one | :many,
               relationship: :parent | :child,
               owner: atom,
               owner_key: atom,
               field: atom,
               unique: boolean}

  alias Ecto.Query.{BooleanExpr, QueryExpr}

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

    * `:relationship` - if the relationship to the specified schema is
      of a `:child` or a `:parent`

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

  Receives the parent changeset, the current changesets
  and the repository action options. Must return the
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
  Build an association query through with starting the given reflection
  and through the given associations.
  """
  def assoc_query(refl, through, query, values)

  def assoc_query(%{owner: owner, through: [h|t], field: field}, extra, query, values) do
    refl = owner.__schema__(:association, h) ||
            raise "unknown association `#{h}` for `#{inspect owner}` (used by through association `#{field}`)"
    assoc_query refl, t ++ extra, query, values
  end

  def assoc_query(%module{} = refl, [], query, values) do
    module.assoc_query(refl, query, values)
  end

  def assoc_query(refl, t, query, values) do
    query = query || %Ecto.Query{from: {"join expression", nil}, prefix: refl.queryable.__schema__(:prefix)}

    # Find the position for upcoming joins
    position = length(query.joins) + 1

    # The first association must become a join,
    # so we convert its where (that comes from assoc_query)
    # to a join expression.
    #
    # Note we are being restrictive on the format
    # expected from assoc_query.
    assoc_query = refl.__struct__.assoc_query(refl, nil, values)
    joins = Ecto.Query.Planner.query_to_joins(:inner, assoc_query, position)

    # Add the new join to the query and traverse the remaining
    # joins that will start counting from the added join position.
    query =
      %{query | joins: query.joins ++ joins}
      |> joins_query(t, position + length(joins) - 1)
      |> Ecto.Query.Planner.prepare_sources(:adapter_wont_be_needed)

    # Our source is going to be the last join after
    # traversing them all.
    {joins, [assoc]} = Enum.split(query.joins, -1)

    # Update the mapping and start rewriting expressions
    # to make the last join point to the new from source.
    rewrite_ix = assoc.ix
    [assoc | joins] = Enum.map([assoc | joins], &rewrite_join(&1, rewrite_ix))

    %{query | wheres: [assoc_to_where(assoc) | query.wheres], joins: joins,
              from: merge_from(query.from, assoc.source), sources: nil}
    |> distinct([x], true)
  end

  defp assoc_to_where(%{on: %QueryExpr{} = on}) do
    on
    |> Map.put(:__struct__, BooleanExpr)
    |> Map.put(:op, :and)
  end

  defp merge_from({"join expression", _}, assoc_source), do: assoc_source
  defp merge_from(from, _assoc_source), do: from

  # Rewrite all later joins
  defp rewrite_join(%{on: on, ix: ix} = join, mapping) when ix >= mapping do
    on = Ecto.Query.Planner.rewrite_sources(on, &rewrite_ix(mapping, &1))
    %{join | on: on, ix: rewrite_ix(mapping, ix)}
  end

  # Previous joins are kept intact
  defp rewrite_join(join, _mapping) do
    join
  end

  defp rewrite_ix(mapping, ix) when ix > mapping, do: ix - 1
  defp rewrite_ix(ix, ix), do: 0
  defp rewrite_ix(_mapping, ix), do: ix

  @doc """
  Build a join query with the given `through` associations starting at `counter`.
  """
  def joins_query(query, through, counter) do
    Enum.reduce(through, {query, counter}, fn current, {acc, counter} ->
      query = join(acc, :inner, [x: counter], assoc(x, ^current))
      {query, counter + 1}
    end) |> elem(0)
  end

  @doc """
  Retrieves related module from queryable.

  ## Examples

      iex> Ecto.Association.related_from_query({"custom_source", Schema})
      Schema

      iex> Ecto.Association.related_from_query(Schema)
      Schema

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

  @doc false
  def update_parent_prefix(changeset, parent) do
    case parent do
      %{__meta__: %{source: {prefix, _}}} ->
        update_in changeset.data, &Ecto.put_meta(&1, prefix: prefix)
      _ ->
        changeset
    end
  end

  @doc """
  Performs the repository action in the related changeset,
  returning `{:ok, data}` or `{:error, changes}`.
  """
  def on_repo_change(%{data: struct}, [], _opts) do
    {:ok, struct}
  end

  def on_repo_change(changeset, assocs, opts) do
    %{data: struct, changes: changes, action: action} = changeset

    {struct, changes, _halt, valid?} =
      Enum.reduce(assocs, {struct, changes, false, true}, fn {refl, value}, acc ->
        on_repo_change(refl, value, changeset, action, opts, acc)
      end)

    case valid? do
      true  -> {:ok, struct}
      false -> {:error, changes}
    end
  end

  defp on_repo_change(%{cardinality: :one, field: field} = meta, nil, parent_changeset,
                      _repo_action, opts, {parent, changes, halt, valid?}) do
    if not halt, do: maybe_replace_one!(meta, nil, parent, parent_changeset, opts)
    {Map.put(parent, field, nil), Map.put(changes, field, nil), halt, valid?}
  end

  defp on_repo_change(%{cardinality: :one, field: field, __struct__: mod} = meta,
                      %{action: action} = changeset, parent_changeset,
                      repo_action, opts, {parent, changes, halt, valid?}) do
    check_action!(meta, action, repo_action)
    case on_repo_change_unless_halted(halt, mod, meta, parent_changeset, changeset, opts) do
      {:ok, struct} ->
        struct && maybe_replace_one!(meta, struct, parent, parent_changeset, opts)
        {Map.put(parent, field, struct), Map.put(changes, field, changeset), halt, valid?}
      {:error, error_changeset} ->
        {parent, Map.put(changes, field, error_changeset),
         halted?(halt, changeset, error_changeset), false}
    end
  end

  defp on_repo_change(%{cardinality: :many, field: field, __struct__: mod} = meta,
                      changesets, parent_changeset, repo_action, opts,
                      {parent, changes, halt, all_valid?}) do
    {changesets, structs, halt, valid?} =
      Enum.reduce(changesets, {[], [], halt, true}, fn
        %{action: action} = changeset, {changesets, structs, halt, valid?} ->
          check_action!(meta, action, repo_action)
          case on_repo_change_unless_halted(halt, mod, meta, parent_changeset, changeset, opts) do
            {:ok, nil} ->
              {[changeset|changesets], structs, halt, valid?}
            {:ok, struct} ->
              {[changeset|changesets], [struct | structs], halt, valid?}
            {:error, error_changeset} ->
              {[error_changeset|changesets], structs, halted?(halt, changeset, error_changeset), false}
          end
      end)

    if valid? do
      {Map.put(parent, field, Enum.reverse(structs)),
       Map.put(changes, field, Enum.reverse(changesets)),
       halt, all_valid?}
    else
      {parent,
       Map.put(changes, field, Enum.reverse(changesets)),
       halt, false}
    end
  end

  defp check_action!(%{related: schema}, :delete, :insert),
    do: raise(ArgumentError, "got action :delete in changeset for associated #{inspect schema} while inserting")
  defp check_action!(_, _, _), do: :ok

  defp halted?(true, _, _), do: true
  defp halted?(_, %{valid?: true}, %{valid?: false}), do: true
  defp halted?(_, _, _), do: false

  defp on_repo_change_unless_halted(true, _mod, _meta, _parent, changeset, _opts) do
    {:error, changeset}
  end
  defp on_repo_change_unless_halted(false, mod, meta, parent, changeset, opts) do
    mod.on_repo_change(meta, parent, changeset, opts)
  end

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
    * `relationship` - The relationship to the specified schema, default is `:child`
  """

  @behaviour Ecto.Association
  @on_delete_opts [:nothing, :nilify_all, :delete_all]
  @on_replace_opts [:raise, :mark_as_invalid, :delete, :nilify]
  @has_one_on_replace_opts @on_replace_opts ++ [:update]
  defstruct [:cardinality, :field, :owner, :related, :owner_key, :related_key, :on_cast,
             :queryable, :on_delete, :on_replace, unique: true, defaults: [], relationship: :child]

  @doc false
  def struct(module, name, opts) do
    ref =
      module
      |> Module.get_attribute(:primary_key)
      |> get_ref(opts[:references], name)

    unless Module.get_attribute(module, :ecto_fields)[ref] do
      raise ArgumentError, "schema does not have the field #{inspect ref} used by " <>
        "association #{inspect name}, please set the :references option accordingly"
    end

    queryable = Keyword.fetch!(opts, :queryable)
    cardinality = Keyword.fetch!(opts, :cardinality)
    related = Ecto.Association.related_from_query(queryable)

    if opts[:through] do
      raise ArgumentError, "invalid association #{inspect name}. When using the :through " <>
                           "option, the schema should not be passed as second argument"
    end

    on_delete  = Keyword.get(opts, :on_delete, :nothing)
    unless on_delete in @on_delete_opts do
      raise ArgumentError, "invalid :on_delete option for #{inspect name}. " <>
        "The only valid options are: " <>
        Enum.map_join(@on_delete_opts, ", ", &"`#{inspect &1}`")
    end

    on_replace = Keyword.get(opts, :on_replace, :raise)
    on_replace_opts = if cardinality == :one, do: @has_one_on_replace_opts, else: @on_replace_opts

    unless on_replace in on_replace_opts do
      raise ArgumentError, "invalid `:on_replace` option for #{inspect name}. " <>
        "The only valid options are: " <>
        Enum.map_join(@on_replace_opts, ", ", &"`#{inspect &1}`")
    end

    %__MODULE__{
      field: name,
      cardinality: cardinality,
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

  defp get_ref(nil, nil, name) do
    raise ArgumentError, "need to set :references option for " <>
      "association #{inspect name} when schema has no primary key"
  end
  defp get_ref(primary_key, nil, _name), do: elem(primary_key, 0)
  defp get_ref(_primary_key, references, _name), do: references

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
  def assoc_query(%{queryable: queryable, related_key: related_key}, query, [value]) do
    from x in (query || queryable),
      where: field(x, ^related_key) == ^value
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
  def on_repo_change(%{on_replace: on_replace} = refl, %{data: parent} = parent_changeset,
                     %{action: :replace} = changeset, opts) do
    changeset = case on_replace do
      :nilify -> %{changeset | action: :update}
      :delete -> %{changeset | action: :delete}
    end

    changeset = Ecto.Association.update_parent_prefix(changeset, parent)

    case on_repo_change(refl, %{parent_changeset | data: nil}, changeset, opts) do
      {:ok, _} -> {:ok, nil}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def on_repo_change(assoc, parent_changeset, changeset, opts) do
    %{data: parent, repo: repo} = parent_changeset
    %{action: action, changes: changes} = changeset

    {key, value} = parent_key(assoc, parent)
    changeset = update_parent_key(changeset, action, key, value)
    changeset = Ecto.Association.update_parent_prefix(changeset, parent)

    case apply(repo, action, [changeset, opts]) do
      {:ok, _} = ok ->
        if action == :delete, do: {:ok, nil}, else: ok
      {:error, changeset} ->
        original = Map.get(changes, key)
        {:error, put_in(changeset.changes[key], original)}
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
    * `relationship` - The relationship to the specified schema, default `:child`
  """

  @behaviour Ecto.Association
  defstruct [:cardinality, :field, :owner, :owner_key, :through, :on_cast,
             relationship: :child, unique: true]

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
    Ecto.Association.joins_query(owner, through, 0)
  end

  @doc false
  def assoc_query(refl, query, values) do
    Ecto.Association.assoc_query(refl, [], query, values)
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
    * `relationship` - The relationship to the specified schema, default `:parent`
    * `on_replace` - The action taken on associations when schema is replaced
  """

  @behaviour Ecto.Association
  @on_replace_opts [:raise, :mark_as_invalid, :delete, :nilify, :update]
  defstruct [:field, :owner, :related, :owner_key, :related_key, :queryable, :on_cast,
             :on_replace, defaults: [], cardinality: :one, relationship: :parent, unique: true]

  @doc false
  def struct(module, name, opts) do
    ref       = if ref = opts[:references], do: ref, else: :id
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
  def assoc_query(%{queryable: queryable, related_key: related_key}, query, [value]) do
    from x in (query || queryable),
      where: field(x, ^related_key) == ^value
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

  def on_repo_change(_refl, %{data: parent, repo: repo}, %{action: action} = changeset, opts) do
    changeset = Ecto.Association.update_parent_prefix(changeset, parent)

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
    * `relationship` - The relationship to the specified schema, default `:child`
    * `join_keys` - The keyword list with many to many join keys
    * `join_through` - Atom (representing a schema) or a string (representing a table)
      for many to many associations
  """

  @behaviour Ecto.Association
  @on_delete_opts [:nothing, :delete_all]
  @on_replace_opts [:raise, :mark_as_invalid, :delete]
  defstruct [:field, :owner, :related, :owner_key, :queryable, :on_delete,
             :on_replace, :join_keys, :join_through, :on_cast,
             defaults: [], relationship: :child, cardinality: :many, unique: false]

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
      defaults: opts[:defaults] || [],
      unique: Keyword.get(opts, :unique, false)
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
                    queryable: queryable, owner: owner}, query, values) do
    [{join_owner_key, owner_key}, {join_related_key, related_key}] = join_keys

    # We need to go all the way using owner and query so
    # Ecto has all the information necessary to cast fields.
    # This also helps validate the associated schema exists all the way.
    from q in (query || queryable),
      join: o in ^owner, on: field(o, ^owner_key) in ^values,
      join: j in ^join_through, on: field(j, ^join_owner_key) == field(o, ^owner_key),
      where: field(j, ^join_related_key) == field(q, ^related_key)
  end

  @doc false
  def build(refl, _, attributes) do
    refl
    |> build()
    |> struct(attributes)
  end

  @doc false
  def preload_info(%{join_keys: [{_, owner_key}, {_, _}]} = refl) do
    {:assoc, refl, {-2, owner_key}}
  end

  @doc false
  def on_repo_change(%{on_replace: :delete} = refl, parent_changeset,
                     %{action: :replace}  = changeset, opts) do
    on_repo_change(refl, parent_changeset, %{changeset | action: :delete}, opts)
  end

  def on_repo_change(%{join_keys: join_keys, join_through: join_through},
                     %{repo: repo, data: owner}, %{action: :delete, data: related}, opts) do
    [{join_owner_key, owner_key}, {join_related_key, related_key}] = join_keys

    adapter = repo.__adapter__()
    owner_value = dump! :delete, join_through, owner, owner_key, adapter
    related_value = dump! :delete, join_through, related, related_key, adapter

    query =
      from j in join_through,
        where: field(j, ^join_owner_key) == ^owner_value and
               field(j, ^join_related_key) == ^related_value

    {prefix, _} = owner.__meta__.source
    query = Map.put(query, :prefix, prefix)

    repo.delete_all query, opts
    {:ok, nil}
  end

  def on_repo_change(%{field: field, join_through: join_through, join_keys: join_keys},
                     %{repo: repo, data: owner, constraints: constraints} = parent_changeset,
                     %{action: action} = changeset, opts) do
    changeset = Ecto.Association.update_parent_prefix(changeset, owner)

    case apply(repo, action, [changeset, opts]) do
      {:ok, related} ->
        [{join_owner_key, owner_key}, {join_related_key, related_key}] = join_keys
        if insert_join?(parent_changeset, changeset, field, related_key) do
          adapter = repo.__adapter__()
          owner_value = dump! :insert, join_through, owner, owner_key, adapter
          related_value = dump! :insert, join_through, related, related_key, adapter

          data = [{join_owner_key, owner_value}, {join_related_key, related_value}]

          case insert_join(repo, join_through, data, opts, constraints) do
            {:error, join_changeset} ->
              {:error, %{changeset | errors: join_changeset.errors ++ changeset.errors,
                                     valid?: join_changeset.valid? and changeset.valid?}}
            _ ->
              {:ok, related}
          end
        else
          {:ok, related}
        end
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp insert_join?(%{action: :insert}, _, _field, _related_key), do: true
  defp insert_join?(_, %{action: :insert}, _field, _related_key), do: true
  defp insert_join?(%{data: owner}, %{data: related}, field, related_key) do
    current_key = Map.fetch!(related, related_key)
    not Enum.any? Map.fetch!(owner, field), fn child ->
      Map.get(child, related_key) == current_key
    end
  end

  defp insert_join(repo, join_through, data, opts, _constraints) when is_binary(join_through) do
    repo.insert_all join_through, [data], opts
  end

  defp insert_join(repo, join_through, data, opts, constraints) when is_atom(join_through) do
    struct(join_through, data)
    |> Ecto.Changeset.change
    |> Map.put(:constraints, constraints)
    |> repo.insert(opts)
  end

  defp field!(op, struct, field) do
    Map.get(struct, field) || raise "could not #{op} join entry because `#{field}` is nil in #{inspect struct}"
  end

  defp dump!(action, join_through, struct, field, adapter) when is_binary(join_through) do
    value = field!(action, struct, field)
    type  = struct.__struct__.__schema__(:type, field)
    case Ecto.Type.adapter_dump(adapter, type, value) do
      {:ok, value} ->
        value
      :error ->
        raise Ecto.ChangeError,
          message: "value `#{inspect value}` for `#{inspect struct.__struct__}.#{field}` " <>
                   "in `#{action}` does not match type #{inspect type}"
    end
  end

  defp dump!(action, join_through, struct, field, _) when is_atom(join_through) do
    field!(action, struct, field)
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
  def delete_all(%{join_through: join_through, join_keys: join_keys, owner: owner}, parent, repo, opts) do
    [{join_owner_key, owner_key}, {_, _}] = join_keys
    if value = Map.get(parent, owner_key) do
      owner_type = owner.__schema__(:type, owner_key)
      query = from j in join_through, where: field(j, ^join_owner_key) == type(^value, ^owner_type)
      repo.delete_all query, opts
    end
  end
end
