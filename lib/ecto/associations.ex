import Ecto.Query, only: [from: 2, join: 4, distinct: 3, select: 3]

defmodule Ecto.Associations do
  @moduledoc """
  Documents the functions required for associations to implement
  in order to work with Ecto query mechanism.

  This module contains documentation for those interested in
  understanding how Ecto associations work internally. If you are
  interested in an overview about associations in Ecto, you should
  look into the documentation for `Ecto` and `Ecto.Schema`
  modules.

  ## Associations

  Associations work in Ecto via behaviours. Anyone can add new
  associations to Ecto as long as they implement the callbacks
  specified in this module.

  Note though that, since the associations API is in development,
  existing callbacks signature and new callbacks can be added
  in upcoming Ecto releases.
  """

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

  Invoked by `Ecto.Model.build/2`.
  """
  defcallback build(t, Ecto.Model.t) :: Ecto.Model.t

  @doc """
  Returns an association join query.

  This callback receives the association struct and it must return
  a query that retrieves all associated objects using joins up to
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
  a query that retrieves all associated objects with the given
  values for the owner key.

  This callback is used by `Ecto.Model.assoc/2`.
  """
  defcallback assoc_query(t, values :: [term]) :: Ecto.Query.t

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
  Returns the association key for the given module with the given prefix.

  ## Examples

      iex> Ecto.Associations.association_key(Hello.World, :id)
      :world_id

      iex> Ecto.Associations.association_key(Hello.HTTP, :id)
      :http_id

      iex> Ecto.Associations.association_key(Hello.HTTPServer, :id)
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
end

defmodule Ecto.Associations.NotLoaded do
  @moduledoc """
  Struct returned by one to one associations when there are not loaded.

  The fields are:

    * `__field__` - the association field in `__owner__`
    * `__owner__` - the model that owns the association

  """
  defstruct [:__field__, :__owner__]

  defimpl Inspect do
    def inspect(not_loaded, _opts) do
      msg = "association #{inspect not_loaded.__field__} is not loaded"
      ~s(#Ecto.Associations.NotLoaded<#{msg}>)
    end
  end
end

defmodule Ecto.Associations.Has do
  @moduledoc """
  The association struct for `has_one` and `has_many` associations.

  Its fields are:

    * `cardinality` - The association cardinality
    * `field` - The name of the association field on the model
    * `owner` - The model where the association was defined
    * `assoc` - The model that is associated
    * `owner_key` - The key on the `owner` model used for the association
    * `assoc_key` - The key on the `associated` model used for the association
  """

  @behaviour Ecto.Associations
  defstruct [:cardinality, :field, :owner, :assoc, :owner_key, :assoc_key]

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

    assoc = Keyword.fetch!(opts, :queryable)

    unless is_atom(assoc) do
      raise ArgumentError, "association queryable must be a model, got: #{inspect assoc}"
    end

    if opts[:through] do
      raise ArgumentError, "invalid association #{inspect name}. When using the :through " <>
                           "option, the model should not be passed as second argument"
    end

    %__MODULE__{
      field: name,
      cardinality: Keyword.fetch!(opts, :cardinality),
      owner: module,
      assoc: assoc,
      owner_key: ref,
      assoc_key: opts[:foreign_key] || Ecto.Associations.association_key(module, ref)
    }
  end

  @doc false
  def build(%{assoc: assoc, owner_key: owner_key, assoc_key: assoc_key}, struct) do
    Map.put apply(assoc, :__struct__, []), assoc_key, Map.get(struct, owner_key)
  end

  @doc false
  def joins_query(refl) do
    from o in refl.owner,
      join: q in ^refl.assoc,
      on: field(q, ^refl.assoc_key) == field(o, ^refl.owner_key)
  end

  @doc false
  def assoc_query(refl, values) do
    from x in refl.assoc,
      where: field(x, ^refl.assoc_key) in ^values
  end

  @doc false
  def preload_info(refl) do
    {:assoc, refl, refl.assoc_key}
  end
end

defmodule Ecto.Associations.HasThrough do
  @moduledoc """
  The association struct for `has_one` and `has_many` through associations.

  Its fields are:

    * `cardinality` - The association cardinality
    * `field` - The name of the association field on the model
    * `owner` - The model where the association was defined
    * `owner_key` - The key on the `owner` model used for the association
    * `through` - The through associations
  """

  @behaviour Ecto.Associations
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
  def build(%{field: name}, %{__struct__: struct}) do
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
    joins_query(owner, through)
  end

  defp joins_query(query, through) do
    Enum.reduce(through, {query, 0}, fn current, {acc, counter} ->
      {join(acc, :inner, [x: counter], assoc(x, ^current)), counter + 1}
    end) |> elem(0)
  end

  @doc false
  def assoc_query(%{owner: owner, through: [h|t]}, values) do
    refl  = owner.__schema__(:association, h)

    query =
      refl.__struct__.assoc_query(refl, values)
      |> joins_query(t)
      |> Ecto.Query.Planner.prepare_sources()

    {joins, {mapping, last}} = rewrite_joins(query)
    wheres = rewrite_many(query.wheres, mapping)

    {_, model} = from = last.source
    [_|joins]  = Enum.reverse([%{last | source: query.from}|joins])

    pk = model.__schema__(:primary_key) ||
          raise Ecto.NoPrimaryKeyError, model: model

    %{query | from: from, joins: joins, wheres: wheres, sources: nil}
    |> distinct([x], field(x, ^pk))
    |> select([x], x)
  end

  alias Ecto.Query.JoinExpr

  defp rewrite_joins(query) do
    count = length(query.joins)

    Enum.map_reduce(query.joins, {%{0 => count}, nil}, fn
      %JoinExpr{ix: ix, on: on} = join, {acc, _} ->
        acc  = Map.put(acc, ix, count - Map.size(acc))
        join = %{join | ix: nil, on: rewrite_expr(on, acc)}
        {join, {acc, join}}
    end)
  end

  defp rewrite_expr(%{expr: expr, params: params} = part, mapping) do
    expr =
      Macro.prewalk expr, fn
        {:&, meta, [ix]} ->
          {:&, meta, [Map.fetch!(mapping, ix)]}
        other ->
          other
      end

    params =
      Enum.reduce params, params, fn
        {key, {val, {composite, {ix, field}}}}, acc when is_integer(ix) ->
          Map.put(acc, key, {val, {composite, {Map.fetch!(mapping, ix), field}}})
        {key, {val, {ix, field}}}, acc when is_integer(ix) ->
          Map.put(acc, key, {val, {Map.fetch!(mapping, ix), field}})
        {_, _}, acc ->
          acc
      end

    %{part | expr: expr, params: params}
  end

  defp rewrite_many(exprs, acc) do
    Enum.map(exprs, &rewrite_expr(&1, acc))
  end
end

defmodule Ecto.Associations.BelongsTo do
  @moduledoc """
  The association struct for a `belongs_to` association.

  Its fields are:

    * `cardinality` - The association cardinality
    * `field` - The name of the association field on the model
    * `owner` - The model where the association was defined
    * `assoc` - The model that is associated
    * `owner_key` - The key on the `owner` model used for the association
    * `assoc_key` - The key on the `assoc` model used for the association
  """

  @behaviour Ecto.Associations
  defstruct [:cardinality, :field, :owner, :assoc, :owner_key, :assoc_key]

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

    assoc = Keyword.fetch!(opts, :queryable)

    unless is_atom(assoc) do
      raise ArgumentError, "association queryable must be a model, got: #{inspect assoc}"
    end

    %__MODULE__{
      field: name,
      cardinality: :one,
      owner: module,
      assoc: assoc,
      owner_key: Keyword.fetch!(opts, :foreign_key),
      assoc_key: ref
    }
  end

  @doc false
  def build(%{assoc: assoc}, _struct) do
    apply(assoc, :__struct__, [])
  end

  @doc false
  def joins_query(refl) do
    from o in refl.owner,
      join: q in ^refl.assoc,
      on: field(q, ^refl.assoc_key) == field(o, ^refl.owner_key)
  end

  @doc false
  def assoc_query(refl, values) do
    from x in refl.assoc,
      where: field(x, ^refl.assoc_key) in ^values
  end

  @doc false
  def preload_info(refl) do
    {:assoc, refl, refl.assoc_key}
  end
end
