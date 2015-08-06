import Ecto.Query, only: [from: 2, join: 4, distinct: 3, select: 3]

defmodule Ecto.Association.NotLoaded do
  @moduledoc """
  Struct returned by one to one associations when they are not loaded.

  The fields are:

    * `__field__` - the association field in `owner`
    * `__owner__` - the model that owns the association
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

  @type t :: %{__struct__: atom, cardinality: :one | :many,
               field: atom, owner_key: atom, owner: atom}
  use Behaviour

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

  """
  defcallback struct(module, field :: atom, opts :: Keyword.t) :: t

  @doc """
  Builds a model for the given association.

  The struct to build from is given as argument in case default values
  should be set in the struct.

  Invoked by `Ecto.Model.build/3`.
  """
  defcallback build(t, Ecto.Model.t, %{atom => term} | [Keyword.t]) :: Ecto.Model.t

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
  defcallback joins_query(t) :: Ecto.Query.t

  @doc """
  Returns the association query.

  This callback receives the association struct and it must return
  a query that retrieves all associated entries with the given
  values for the owner key.

  This callback is used by `Ecto.Model.assoc/2`.
  """
  defcallback assoc_query(t, values :: [term]) :: Ecto.Query.t

  @doc """
  Returns the association query on top of the given query.

  This callback receives the association struct and it must return
  a query that retrieves all associated entries with the given
  values for the owner key.

  This callback is used by preloading.
  """
  defcallback assoc_query(t, Ecto.Query.t, values :: [term]) :: Ecto.Query.t

  @doc """
  Returns information used by the preloader.
  """
  defcallback preload_info(t) ::
              {:assoc, t, atom} | {:through, t, [atom]}

  @doc """
  Retrieves the association from the given model.
  """
  def association_from_model!(model, assoc) do
    model.__schema__(:association, assoc) ||
      raise ArgumentError, "model #{inspect model} does not have association #{inspect assoc}"
  end

  @doc """
  Checks if an association is loaded.

  ## Examples

      post = Repo.get(Post, 1)
      Ecto.Association.loaded?(post.comments) # false
      post = post |> Repo.preload(:comments)
      Ecto.Association.loaded?(post.comments) # true

  """
  def loaded?(association) do
    case association do
      %Ecto.Association.NotLoaded{} -> false
      _ -> true
    end
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
    prefix = module |> Module.split |> List.last |> underscore
    :"#{prefix}_#{suffix}"
  end

  defp underscore(""), do: ""

  defp underscore(<<h, t :: binary>>) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<h, t, rest :: binary>>, _) when h in ?A..?Z and not t in ?A..?Z do
    <<?_, to_lower_char(h), t>> <> do_underscore(rest, t)
  end

  defp do_underscore(<<h, t :: binary>>, prev) when h in ?A..?Z and not prev in ?A..?Z do
    <<?_, to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<?-, t :: binary>>, _) do
    <<?_>> <> do_underscore(t, ?-)
  end

  defp do_underscore(<< "..", t :: binary>>, _) do
    <<"..">> <> underscore(t)
  end

  defp do_underscore(<<?.>>, _), do: <<?.>>

  defp do_underscore(<<?., t :: binary>>, _) do
    <<?/>> <> underscore(t)
  end

  defp do_underscore(<<h, t :: binary>>, _) do
    <<to_lower_char(h)>> <> do_underscore(t, h)
  end

  defp do_underscore(<<>>, _) do
    <<>>
  end

  defp to_lower_char(char) when char in ?A..?Z, do: char + 32
  defp to_lower_char(char), do: char

  @doc """
  Retrieves related module from queryable.

  ## Examples

      iex> Ecto.Association.related_from_query({"custom_source", Model})
      Model

      iex> Ecto.Association.related_from_query(Model)
      Model

      iex> Ecto.Association.related_from_query("wrong")
      ** (ArgumentError) association queryable must be a model or {source, model}, got: "wrong"

  """
  def related_from_query(atom) when is_atom(atom), do: atom
  def related_from_query({source, model}) when is_binary(source) and is_atom(model), do: model
  def related_from_query(queryable) do
    raise ArgumentError, "association queryable must be a model " <>
      "or {source, model}, got: #{inspect queryable}"
  end

  @doc """
  Merges source from query into to the given model.

  In case the query does not have a source, returns
  the model unchanged.
  """
  def merge_source(model, query)

  def merge_source(struct, {source, _}) do
    Ecto.Model.put_source(struct, source)
  end

  def merge_source(struct, _query) do
    struct
  end
end

defmodule Ecto.Association.Has do
  @moduledoc """
  The association struct for `has_one` and `has_many` associations.

  Its fields are:

    * `cardinality` - The association cardinality
    * `field` - The name of the association field on the model
    * `owner` - The model where the association was defined
    * `related` - The model that is associated
    * `owner_key` - The key on the `owner` model used for the association
    * `related_key` - The key on the `related` model used for the association
    * `queryable` - The real query to use for querying association
    * `on_delete` - The action taken on associations when model is deleted
    * `on_replace` - The action taken on associations when model is replaced
    * `on_cast` - The changeset function to call during casting
    * `defaults` - Default fields used when building the association
  """

  @behaviour Ecto.Association
  @on_delete_opts [:nothing, :fetch_and_delete, :nilify_all, :delete_all]
  @on_replace_opts [:delete, :nilify]
  defstruct [:cardinality, :field, :owner, :related, :owner_key, :related_key,
             :queryable, :on_delete, :on_replace, :on_cast, defaults: []]

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
            "association #{inspect name} when model has no primary key"
      end

    unless Module.get_attribute(module, :ecto_fields)[ref] do
      raise ArgumentError, "model does not have the field #{inspect ref} used by " <>
        "association #{inspect name}, please set the :references option accordingly"
    end

    queryable = Keyword.fetch!(opts, :queryable)
    related = Ecto.Association.related_from_query(queryable)

    if opts[:through] do
      raise ArgumentError, "invalid association #{inspect name}. When using the :through " <>
                           "option, the model should not be passed as second argument"
    end

    on_delete  = Keyword.get(opts, :on_delete, :nothing)
    on_replace = Keyword.get(opts, :on_replace, :delete)
    on_cast    = Keyword.get(opts, :on_cast, :changeset)

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
      on_cast: on_cast,
      defaults: opts[:defaults] || []
    }
  end

  @doc false
  def build(%{related: related, owner_key: owner_key, related_key: related_key,
              queryable: queryable, defaults: defaults}, struct, attributes) do
    related
    |> struct(defaults)
    |> struct(attributes)
    |> Map.put(related_key, Map.get(struct, owner_key))
    |> Ecto.Association.merge_source(queryable)
  end

  @doc false
  def joins_query(refl) do
    from o in refl.owner,
      join: q in ^refl.queryable,
      on: field(q, ^refl.related_key) == field(o, ^refl.owner_key)
  end

  @doc false
  def assoc_query(refl, values) do
    assoc_query(refl, refl.queryable, values)
  end

  @doc false
  def assoc_query(refl, query, values) do
    from x in query,
      where: field(x, ^refl.related_key) in ^values
  end

  @doc false
  def preload_info(refl) do
    {:assoc, refl, refl.related_key}
  end

  @behaviour Ecto.Changeset.Relation

  @doc false
  def on_replace(%{on_replace: :delete}, changeset) do
    {:delete, changeset}
  end

  def on_replace(%{on_replace: :nilify, related_key: related_key}, changeset) do
    changeset = update_in changeset.changes, &Map.put(&1, related_key, nil)
    {:update, changeset}
  end

  @doc false
  # TODO: This should be spec'ed somewhere
  def on_repo_action(assoc, changeset, parent, _adapter, repo, repo_action, opts) do
    %{action: action, changes: changes} = changeset
    check_action!(action, repo_action, assoc)

    {key, value} = parent_key(assoc, parent)
    changeset = update_parent_key(changeset, action, key, value)

    case apply(repo, action, [changeset, opts]) do
      {:ok, _} = ok ->
        maybe_replace_one!(assoc, changeset, parent, repo, opts)
        if action == :delete, do: {:ok, nil}, else: ok
      {:error, changeset} ->
        original = Map.get(changes, key)
        {:error, update_in(changeset.changes, &Map.put(&1, key, original))}
    end
  end

  defp update_parent_key(changeset, :delete, _key, _value),
    do: changeset
  defp update_parent_key(changeset, _action, key, value),
    do: update_in(changeset.changes, &Map.put(&1, key, value))

  defp parent_key(%{owner_key: owner_key, related_key: related_key}, owner) do
    {related_key, Map.get(owner, owner_key)}
  end

  defp check_action!(:delete, :insert, %{related: model}),
    do: raise(ArgumentError, "got action :delete in changeset for associated #{inspect model} while inserting")
  defp check_action!(_, _, _), do: :ok

  defp maybe_replace_one!(%{cardinality: :one, field: field} = assoc,
                          %{action: :insert}, parent, repo, opts) do
    case Map.get(parent, field) do
      %Ecto.Association.NotLoaded{} ->
        :ok
      nil ->
        :ok
      previous ->
        {action, changeset} = on_replace(assoc, Ecto.Changeset.change(previous))

        case apply(repo, action, [changeset, opts]) do
          {:ok, _} ->
            :ok
          {:error, changeset} ->
            raise Ecto.InvalidChangesetError, action: action, changeset: changeset
        end
    end
  end

  defp maybe_replace_one!(_, _, _, _, _), do: :ok
end

defmodule Ecto.Association.HasThrough do
  @moduledoc """
  The association struct for `has_one` and `has_many` through associations.

  Its fields are:

    * `cardinality` - The association cardinality
    * `field` - The name of the association field on the model
    * `owner` - The model where the association was defined
    * `owner_key` - The key on the `owner` model used for the association
    * `through` - The through associations
  """

  alias Ecto.Query.JoinExpr

  @behaviour Ecto.Association
  defstruct [:cardinality, :field, :owner, :owner_key, :through]

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
      raise ArgumentError, "model does not have the association #{inspect hd(through)} " <>
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
      "cannot build through association #{inspect name} for #{inspect struct}. " <>
      "Instead build the intermediate steps explicitly."
  end

  @doc false
  def preload_info(refl) do
    {:through, refl, refl.through}
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
  def assoc_query(refl, values) do
    assoc_query(refl, %Ecto.Query{from: {"join expression", nil}}, values)
  end

  @doc false
  def assoc_query(%{owner: owner, through: [h|t]}, %Ecto.Query{} = query, values) do
    refl = owner.__schema__(:association, h)

    # Find the position for upcoming joins
    position = length(query.joins) + 1

    # The first association must become a join,
    # so we convert its where (that comes from assoc_query)
    # to a join expression.
    #
    # Note we are being restrictive on the format
    # expected from assoc_query.
    join = assoc_to_join(refl.__struct__.assoc_query(refl, values), position)

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
    * `field` - The name of the association field on the model
    * `owner` - The model where the association was defined
    * `related` - The model that is associated
    * `owner_key` - The key on the `owner` model used for the association
    * `related_key` - The key on the `related` model used for the association
    * `queryable` - The real query to use for querying association
    * `defaults` - Default fields used when building the association
  """

  @behaviour Ecto.Association
  defstruct [:cardinality, :field, :owner, :related, :owner_key, :related_key, :queryable, defaults: []]

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
            "association #{inspect name} when model has no primary key"
      end

    queryable = Keyword.fetch!(opts, :queryable)

    related = Ecto.Association.related_from_query(queryable)

    unless is_atom(related) do
      raise ArgumentError, "association queryable must be a model, got: #{inspect related}"
    end

    %__MODULE__{
      field: name,
      cardinality: :one,
      owner: module,
      related: related,
      owner_key: Keyword.fetch!(opts, :foreign_key),
      related_key: ref,
      queryable: queryable
    }
  end

  @doc false
  def build(%{field: name}, %{__struct__: struct}, _attributes) do
    raise ArgumentError,
      "cannot build belongs_to association #{inspect name} for #{inspect struct}. " <>
      "Belongs to associations cannot be built with build/3, only the opposide side (has_one/has_many)"
  end

  @doc false
  def joins_query(refl) do
    from o in refl.owner,
      join: q in ^refl.queryable,
      on: field(q, ^refl.related_key) == field(o, ^refl.owner_key)
  end

  @doc false
  def assoc_query(refl, values) do
    assoc_query(refl, refl.queryable, values)
  end

  @doc false
  def assoc_query(refl, query, values) do
    from x in query,
      where: field(x, ^refl.related_key) in ^values
  end

  @doc false
  def preload_info(refl) do
    {:assoc, refl, refl.related_key}
  end
end
