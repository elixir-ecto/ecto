import Ecto.Query, only: [from: 1, from: 2, join: 4, join: 5, distinct: 3, where: 3]

defmodule Ecto.Association.NotLoaded do
  @moduledoc """
  Struct returned by associations when they are not loaded.

  The fields are:

    * `__field__` - the association field in `owner`
    * `__owner__` - the schema that owns the association
    * `__cardinality__` - the cardinality of the association
  """

  @type t :: %__MODULE__{
          __field__: atom(),
          __owner__: any(),
          __cardinality__: atom()
        }

  defstruct [:__field__, :__owner__, :__cardinality__]

  defimpl Inspect do
    def inspect(not_loaded, _opts) do
      msg = "association #{inspect(not_loaded.__field__)} is not loaded"
      ~s(#Ecto.Association.NotLoaded<#{msg}>)
    end
  end
end

defmodule Ecto.Association do
  @moduledoc false

  @type t :: %{
          required(:__struct__) => atom,
          required(:on_cast) => nil | fun,
          required(:cardinality) => :one | :many,
          required(:relationship) => :parent | :child,
          required(:owner) => atom,
          required(:owner_key) => atom,
          required(:field) => atom,
          required(:unique) => boolean,
          optional(atom) => any
        }

  alias Ecto.Query.Builder.OrderBy

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
  @callback struct(module, field :: atom, opts :: Keyword.t()) :: t

  @doc """
  Invoked after the schema is compiled to validate associations.

  Useful for checking if associated modules exist without running
  into deadlocks.
  """
  @callback after_verify_validation(t) :: :ok | {:error, String.t()}

  @doc """
  Builds a struct for the given association.

  The struct to build from is given as argument in case default values
  should be set in the struct.

  Invoked by `Ecto.build_assoc/3`.
  """
  @callback build(t, owner :: Ecto.Schema.t(), %{atom => term} | [Keyword.t()]) :: Ecto.Schema.t()

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
  @callback joins_query(t) :: Ecto.Query.t()

  @doc """
  Returns the association query on top of the given query.

  If the query is `nil`, the association target must be used.

  This callback receives the association struct and it must return
  a query that retrieves all associated entries with the given
  values for the owner key.

  This callback is used by `Ecto.assoc/2` and when preloading.
  """
  @callback assoc_query(t, Ecto.Query.t() | nil, values :: [term]) :: Ecto.Query.t()

  @doc """
  Returns information used by the preloader.
  """
  @callback preload_info(t) ::
              {:assoc, t, {integer, atom} | {integer, atom, Ecto.Type.t()}}
              | {:through, t, [atom]}

  @doc """
  Performs the repository change on the association.

  Receives the parent changeset, the current changesets
  and the repository action options. Must return the
  persisted struct (or nil) or the changeset error.
  """
  @callback on_repo_change(
              t,
              parent :: Ecto.Changeset.t(),
              changeset :: Ecto.Changeset.t(),
              Ecto.Adapter.t(),
              Keyword.t()
            ) ::
              {:ok, Ecto.Schema.t() | nil} | {:error, Ecto.Changeset.t()}

  @doc """
  Retrieves the association from the given schema.
  """
  def association_from_schema!(schema, assoc) do
    schema.__schema__(:association, assoc) ||
      raise ArgumentError, "schema #{inspect(schema)} does not have association #{inspect(assoc)}"
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
    prefix = module |> Module.split() |> List.last() |> Macro.underscore()
    :"#{prefix}_#{suffix}"
  end

  @doc """
  Build an association query through the given associations from the specified owner table
  and through the given associations. Finally filter by the provided values of the owner_key of
  the first relationship in the chain. Used in Ecto.assoc/2.
  """
  def filter_through_chain(owner, through, values) do
    chain_through(owner, through, nil, values)
    |> distinct([x], true)
  end

  @doc """
  Join the target table given a list of associations to go through starting from the owner table.
  """
  def join_through_chain(owner, through, query) do
    chain_through(owner, through, query, nil)
  end

  # This function is used by both join_through_chain/3 and filter_through_chain/3 since the algorithm for both
  # is nearly identical barring a few differences.
  defp chain_through(owner, through, join_to, values) do
    # Flatten the chain of throughs. If any of the associations is a HasThrough this allows us to expand it so we have
    # a list of atomic associations to join through.
    {_, through} = flatten_through_chain(owner, through, [])

    # If we're joining then we're going forward from the owner table to the destination table.
    # Otherwise we're going backward from the destination table then filtering by values.
    chain_direction = if(join_to != nil, do: :forward, else: :backward)

    # This stage produces a list of joins represented as a keyword list with the following structure:
    # [
    #   [schema: (The Schema), in_key: (The key used to join into the table), out_key: (The key used to join with the next), where: (The condition KW list)]
    # ]
    relation_list = resolve_through_tables(owner, through, chain_direction)

    # Filter out the joins which are redundant
    filtered_list =
      Enum.with_index(relation_list)
      |> Enum.filter(fn
        # We always keep the first table in the chain since it's our source table for the query
        {_, 0} ->
          true

        {rel, _} ->
          # If the condition is not empty we need to join to the table. Otherwise if the in_key and out_key is the same
          # then this join is redundant since we can just join to the next table in the chain.
          rel.in_key != rel.out_key or rel.where != []
      end)
      |> Enum.map(&elem(&1, 0))

    # If we're preloading we don't need the last table since it is the owner table.
    filtered_list = if(join_to == nil, do: Enum.drop(filtered_list, -1), else: filtered_list)

    [source | joins] = filtered_list

    source_schema = source.schema
    query = join_to || from(s in source_schema)

    counter = Ecto.Query.Builder.count_binds(query) - 1

    # We need to create the query by joining all the tables, and also we need the out_key of the final table to use
    # for the final WHERE clause with values.
    {_, query, _, dest_out_key} =
      Enum.reduce(joins, {source, query, counter, source.out_key}, fn
        curr_rel, {prev_rel, query, counter, _} ->
          related_queryable = curr_rel.schema

          next =
            join(query, :inner, [{src, counter}], dest in ^related_queryable,
              on: field(src, ^prev_rel.out_key) == field(dest, ^curr_rel.in_key)
            )
            |> combine_joins_query(curr_rel.where, counter + 1)

          {curr_rel, next, counter + 1, curr_rel.out_key}
      end)

    final_bind = Ecto.Query.Builder.count_binds(query) - 1

    values = List.wrap(values)

    query =
      case {join_to, values} do
        {nil, [single_value]} ->
          where(query, [{dest, final_bind}], field(dest, ^dest_out_key) == ^single_value)

        {nil, values} ->
          where(query, [{dest, final_bind}], field(dest, ^dest_out_key) in ^values)

        {_, _} ->
          query
      end

    combine_assoc_query(query, source.where || [])
  end

  defp flatten_through_chain(owner, [], acc), do: {owner, acc}

  defp flatten_through_chain(owner, [assoc | tl], acc) do
    refl = association_from_schema!(owner, assoc)

    case refl do
      %{through: nested_throughs} ->
        {owner, acc} = flatten_through_chain(owner, nested_throughs, acc)
        flatten_through_chain(owner, tl, acc)

      _ ->
        flatten_through_chain(refl.related, tl, acc ++ [assoc])
    end
  end

  defp resolve_through_tables(owner, through, :backward) do
    # This step generates a list of maps with the following keys:
    # [
    #   %{schema: ..., out_key: ..., in_key: ..., where: ...}
    # ]
    # This is a list of all tables that we will need to join to follow the chain of throughs and which key is used
    # to join in and out of the table, along with the where condition for that table. The final table of the chain will
    # be "owner", and the first table of the chain will be the final destination table of all the throughs.
    initial_owner_map = %{schema: owner, out_key: nil, in_key: nil, where: nil}

    Enum.reduce(through, {owner, [initial_owner_map]}, fn assoc, {owner, table_list} ->
      refl = association_from_schema!(owner, assoc)
      [owner_map | table_list] = table_list

      table_list =
        case refl do
          %{
            join_through: join_through,
            join_keys: join_keys,
            join_where: join_where,
            where: where
          } ->
            [{owner_join_key, owner_key}, {related_join_key, related_key}] = join_keys

            owner_map = %{owner_map | in_key: owner_key}

            join_map = %{
              schema: join_through,
              out_key: owner_join_key,
              in_key: related_join_key,
              where: join_where
            }

            related_map = %{schema: refl.related, out_key: related_key, in_key: nil, where: where}

            [related_map, join_map, owner_map | table_list]

          _ ->
            owner_map = %{owner_map | in_key: refl.owner_key}

            related_map = %{
              schema: refl.related,
              out_key: refl.related_key,
              in_key: nil,
              where: refl.where
            }

            [related_map, owner_map | table_list]
        end

      {refl.related, table_list}
    end)
    |> elem(1)
  end

  defp resolve_through_tables(owner, through, :forward) do
    # In the forward case (joining) we need to reverse the list and swap the in_key for the out_key
    # since we've changed directions.
    resolve_through_tables(owner, through, :backward)
    |> Enum.reverse()
    |> Enum.map(fn %{out_key: out_key, in_key: in_key} = join ->
      %{join | out_key: in_key, in_key: out_key}
    end)
  end

  @doc """
  Add the default assoc query where clauses to a join.

  This handles only `where` and converts it to a `join`,
  as that is the only information propagate in join queries.
  """
  def combine_joins_query(query, [], _binding), do: query

  def combine_joins_query(%{joins: joins} = query, [_ | _] = conditions, binding) do
    {joins, [join_expr]} = Enum.split(joins, -1)
    %{on: %{params: params, expr: expr} = join_on} = join_expr
    {expr, params} = expand_where(conditions, expr, Enum.reverse(params), length(params), binding)
    %{query | joins: joins ++ [%{join_expr | on: %{join_on | expr: expr, params: params}}]}
  end

  @doc """
  Add the default assoc query where clauses a provided query.
  """
  def combine_assoc_query(query, []), do: query

  def combine_assoc_query(%{wheres: []} = query, conditions) do
    {expr, params} = expand_where(conditions, true, [], 0, 0)

    bool_expr = %Ecto.Query.BooleanExpr{
      op: :and,
      expr: expr,
      params: params,
      line: __ENV__.line,
      file: __ENV__.file
    }

    %{query | wheres: [bool_expr]}
  end

  def combine_assoc_query(%{wheres: wheres} = query, conditions) do
    {wheres, [where_expr]} = Enum.split(wheres, -1)
    %{params: params, expr: expr} = where_expr
    {expr, params} = expand_where(conditions, expr, Enum.reverse(params), length(params), 0)
    %{query | wheres: wheres ++ [%{where_expr | expr: expr, params: params}]}
  end

  defp expand_where(conditions, expr, params, counter, binding) do
    conjoin_exprs = fn
      true, r -> r
      l, r -> {:and, [], [l, r]}
    end

    {expr, params, _counter} =
      Enum.reduce(conditions, {expr, params, counter}, fn
        {key, nil}, {expr, params, counter} ->
          expr = conjoin_exprs.(expr, {:is_nil, [], [to_field(binding, key)]})
          {expr, params, counter}

        {key, {:not, nil}}, {expr, params, counter} ->
          expr = conjoin_exprs.(expr, {:not, [], [{:is_nil, [], [to_field(binding, key)]}]})
          {expr, params, counter}

        {key, {:fragment, frag}}, {expr, params, counter} when is_binary(frag) ->
          pieces = Ecto.Query.Builder.fragment_pieces(frag, [to_field(binding, key)])
          expr = conjoin_exprs.(expr, {:fragment, [], pieces})
          {expr, params, counter}

        {key, {:in, value}}, {expr, params, counter} when is_list(value) ->
          expr = conjoin_exprs.(expr, {:in, [], [to_field(binding, key), {:^, [], [counter]}]})
          {expr, [{value, {:in, {binding, key}}} | params], counter + 1}

        {key, value}, {expr, params, counter} ->
          expr = conjoin_exprs.(expr, {:==, [], [to_field(binding, key), {:^, [], [counter]}]})
          {expr, [{value, {binding, key}} | params], counter + 1}
      end)

    {expr, Enum.reverse(params)}
  end

  defp to_field(binding, field),
    do: {{:., [], [{:&, [], [binding]}, field]}, [], []}

  @doc """
  Build a join query with the given `through` associations starting at `counter`.
  """
  def joins_query(query, through, counter) do
    Enum.reduce(through, {query, counter}, fn current, {acc, counter} ->
      query = join(acc, :inner, [{x, counter}], assoc(x, ^current))
      {query, counter + 1}
    end)
    |> elem(0)
  end

  @doc """
  Retrieves related module from queryable.

  ## Examples

      iex> Ecto.Association.related_from_query({"custom_source", Schema}, :comments_v1)
      Schema

      iex> Ecto.Association.related_from_query(Schema, :comments_v1)
      Schema

      iex> Ecto.Association.related_from_query("wrong", :comments_v1)
      ** (ArgumentError) association :comments_v1 queryable must be a schema or a {source, schema}. got: "wrong"
  """
  def related_from_query(atom, _name) when is_atom(atom), do: atom

  def related_from_query({source, schema}, _name) when is_binary(source) and is_atom(schema),
    do: schema

  def related_from_query(queryable, name) do
    raise ArgumentError,
          "association #{inspect(name)} queryable must be a schema or " <>
            "a {source, schema}. got: #{inspect(queryable)}"
  end

  @doc """
  Applies default values into the struct.
  """
  def apply_defaults(struct, defaults, _owner) when is_list(defaults) do
    struct(struct, defaults)
  end

  def apply_defaults(struct, {mod, fun, args}, owner) do
    apply(mod, fun, [struct.__struct__(), owner | args])
  end

  @doc """
  Validates `defaults` for association named `name`.
  """
  def validate_defaults!(_module, _name, {mod, fun, args} = defaults)
      when is_atom(mod) and is_atom(fun) and is_list(args),
      do: defaults

  def validate_defaults!(module, _name, fun) when is_atom(fun),
    do: {module, fun, []}

  def validate_defaults!(_module, _name, defaults) when is_list(defaults),
    do: defaults

  def validate_defaults!(_module, name, defaults) do
    raise ArgumentError,
          "expected defaults for #{inspect(name)} to be a keyword list " <>
            "or a {module, fun, args} tuple, got: `#{inspect(defaults)}`"
  end

  @doc """
  Validates `preload_order` for association named `name`.
  """
  def validate_preload_order!(_name, {mod, fun, args} = preload_order)
      when is_atom(mod) and is_atom(fun) and is_list(args),
      do: preload_order

  def validate_preload_order!(name, preload_order) when is_list(preload_order) do
    Enum.map(preload_order, fn
      field when is_atom(field) ->
        field

      {direction, field} when is_atom(direction) and is_atom(field) ->
        unless OrderBy.valid_direction?(direction) do
          raise ArgumentError,
                "expected `:preload_order` for #{inspect(name)} to be a keyword list or a list of atoms/fields, " <>
                  "got: `#{inspect(preload_order)}`, " <>
                  "`#{inspect(direction)}` is not a valid direction"
        end

        {direction, field}

      item ->
        raise ArgumentError,
              "expected `:preload_order` for #{inspect(name)} to be a keyword list or a list of atoms/fields, " <>
                "got: `#{inspect(preload_order)}`, " <>
                "`#{inspect(item)}` is not valid"
    end)
  end

  def validate_preload_order!(name, preload_order) do
    raise ArgumentError,
          "expected `:preload_order` for #{inspect(name)} to be a keyword list, a list of atoms/fields " <>
            "or a {Mod, fun, args} tuple, got: `#{inspect(preload_order)}`"
  end

  @doc """
  Merges source from query into to the given schema.

  In case the query does not have a source, returns
  the schema unchanged.
  """
  def merge_source(schema, query)

  def merge_source(%{__meta__: %{source: source}} = struct, {source, _}) do
    struct
  end

  def merge_source(struct, {source, _}) do
    Ecto.put_meta(struct, source: source)
  end

  def merge_source(struct, _query) do
    struct
  end

  @doc """
  Updates the prefix of a changeset based on the metadata.
  """
  def update_parent_prefix(
        %{data: %{__meta__: %{prefix: prefix}}} = changeset,
        %{__meta__: %{prefix: prefix}}
      ),
      do: changeset

  def update_parent_prefix(
        %{data: %{__meta__: %{prefix: nil}}} = changeset,
        %{__meta__: %{prefix: prefix}}
      ),
      do: update_in(changeset.data, &Ecto.put_meta(&1, prefix: prefix))

  def update_parent_prefix(changeset, _),
    do: changeset

  @doc """
  Performs the repository action in the related changeset,
  returning `{:ok, data}` or `{:error, changes}`.
  """
  def on_repo_change(%{data: struct}, [], _adapter, _opts) do
    {:ok, struct}
  end

  def on_repo_change(changeset, assocs, adapter, opts) do
    %{data: struct, changes: changes, action: action} = changeset

    {struct, changes, _halt, valid?} =
      Enum.reduce(assocs, {struct, changes, false, true}, fn {refl, value}, acc ->
        on_repo_change(refl, value, changeset, action, adapter, opts, acc)
      end)

    case valid? do
      true -> {:ok, struct}
      false -> {:error, changes}
    end
  end

  defp on_repo_change(
         %{cardinality: :one, field: field} = meta,
         nil,
         parent_changeset,
         _repo_action,
         adapter,
         opts,
         {parent, changes, halt, valid?}
       ) do
    if not halt, do: maybe_replace_one!(meta, nil, parent, parent_changeset, adapter, opts)
    {Map.put(parent, field, nil), Map.put(changes, field, nil), halt, valid?}
  end

  defp on_repo_change(
         %{cardinality: :one, field: field, __struct__: mod} = meta,
         %{action: action, data: current} = changeset,
         parent_changeset,
         repo_action,
         adapter,
         opts,
         {parent, changes, halt, valid?}
       ) do
    check_action!(meta, action, repo_action)
    if not halt, do: maybe_replace_one!(meta, current, parent, parent_changeset, adapter, opts)

    case on_repo_change_unless_halted(halt, mod, meta, parent_changeset, changeset, adapter, opts) do
      {:ok, struct} ->
        {Map.put(parent, field, struct), Map.put(changes, field, changeset), halt, valid?}

      {:error, error_changeset} ->
        {parent, Map.put(changes, field, error_changeset),
         halted?(halt, changeset, error_changeset), false}
    end
  end

  defp on_repo_change(
         %{cardinality: :many, field: field, __struct__: mod} = meta,
         changesets,
         parent_changeset,
         repo_action,
         adapter,
         opts,
         {parent, changes, halt, all_valid?}
       ) do
    {changesets, structs, halt, valid?} =
      Enum.reduce(changesets, {[], [], halt, true}, fn
        %{action: action} = changeset, {changesets, structs, halt, valid?} ->
          check_action!(meta, action, repo_action)

          case on_repo_change_unless_halted(
                 halt,
                 mod,
                 meta,
                 parent_changeset,
                 changeset,
                 adapter,
                 opts
               ) do
            {:ok, nil} ->
              {[changeset | changesets], structs, halt, valid?}

            {:ok, struct} ->
              {[changeset | changesets], [struct | structs], halt, valid?}

            {:error, error_changeset} ->
              {[error_changeset | changesets], structs, halted?(halt, changeset, error_changeset),
               false}
          end
      end)

    if valid? do
      {Map.put(parent, field, Enum.reverse(structs)),
       Map.put(changes, field, Enum.reverse(changesets)), halt, all_valid?}
    else
      {parent, Map.put(changes, field, Enum.reverse(changesets)), halt, false}
    end
  end

  defp check_action!(%{related: schema}, :delete, :insert) do
    raise ArgumentError,
          "got action :delete in changeset for associated #{inspect(schema)} while inserting"
  end

  defp check_action!(_, _, _), do: :ok

  defp halted?(true, _, _), do: true
  defp halted?(_, %{valid?: true}, %{valid?: false}), do: true
  defp halted?(_, _, _), do: false

  defp on_repo_change_unless_halted(true, _mod, _meta, _parent, changeset, _adapter, _opts) do
    {:error, changeset}
  end

  defp on_repo_change_unless_halted(false, mod, meta, parent, changeset, adapter, opts) do
    mod.on_repo_change(meta, parent, changeset, adapter, opts)
  end

  defp maybe_replace_one!(
         %{field: field, __struct__: mod} = meta,
         current,
         parent,
         parent_changeset,
         adapter,
         opts
       ) do
    previous = Map.get(parent, field)

    if replaceable?(previous) and primary_key!(previous) != primary_key!(current) do
      changeset = %{Ecto.Changeset.change(previous) | action: :replace}

      case mod.on_repo_change(meta, parent_changeset, changeset, adapter, opts) do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          raise Ecto.InvalidChangesetError, action: changeset.action, changeset: changeset
      end
    end
  end

  defp maybe_replace_one!(_, _, _, _, _, _), do: :ok

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
    * `preload_order` - Default `order_by` of the association, used only by preload
  """

  @behaviour Ecto.Association
  @on_delete_opts [:nothing, :nilify_all, :delete_all]
  @on_replace_opts [:raise, :mark_as_invalid, :delete, :delete_if_exists, :nilify]
  @has_one_on_replace_opts @on_replace_opts ++ [:update]
  defstruct [
    :cardinality,
    :field,
    :owner,
    :related,
    :owner_key,
    :related_key,
    :on_cast,
    :queryable,
    :on_delete,
    :on_replace,
    where: [],
    unique: true,
    defaults: [],
    relationship: :child,
    ordered: false,
    preload_order: []
  ]

  @impl true
  def after_verify_validation(%{queryable: queryable, related_key: related_key}) do
    cond do
      not is_atom(queryable) ->
        :ok

      not Code.ensure_loaded?(queryable) ->
        {:error, "associated schema #{inspect(queryable)} does not exist"}

      not function_exported?(queryable, :__schema__, 2) ->
        {:error, "associated module #{inspect(queryable)} is not an Ecto schema"}

      is_nil(queryable.__schema__(:type, related_key)) ->
        {:error, "associated schema #{inspect(queryable)} does not have field `#{related_key}`"}

      true ->
        :ok
    end
  end

  @impl true
  def struct(module, name, opts) do
    queryable = Keyword.fetch!(opts, :queryable)
    cardinality = Keyword.fetch!(opts, :cardinality)
    related = Ecto.Association.related_from_query(queryable, name)

    ref =
      module
      |> Module.get_attribute(:primary_key)
      |> get_ref(opts[:references], name)

    unless Module.get_attribute(module, :ecto_fields)[ref] do
      raise ArgumentError,
            "schema does not have the field #{inspect(ref)} used by " <>
              "association #{inspect(name)}, please set the :references option accordingly"
    end

    if opts[:through] do
      raise ArgumentError,
            "invalid association #{inspect(name)}. When using the :through " <>
              "option, the schema should not be passed as second argument"
    end

    on_delete = Keyword.get(opts, :on_delete, :nothing)

    unless on_delete in @on_delete_opts do
      raise ArgumentError,
            "invalid :on_delete option for #{inspect(name)}. " <>
              "The only valid options are: " <>
              Enum.map_join(@on_delete_opts, ", ", &"`#{inspect(&1)}`")
    end

    on_replace = Keyword.get(opts, :on_replace, :raise)
    on_replace_opts = if cardinality == :one, do: @has_one_on_replace_opts, else: @on_replace_opts

    unless on_replace in on_replace_opts do
      raise ArgumentError,
            "invalid `:on_replace` option for #{inspect(name)}. " <>
              "The only valid options are: " <>
              Enum.map_join(@on_replace_opts, ", ", &"`#{inspect(&1)}`")
    end

    defaults = Ecto.Association.validate_defaults!(module, name, opts[:defaults] || [])
    preload_order = Ecto.Association.validate_preload_order!(name, opts[:preload_order] || [])
    where = opts[:where] || []

    unless is_list(where) do
      raise ArgumentError,
            "expected `:where` for #{inspect(name)} to be a keyword list, got: `#{inspect(where)}`"
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
      defaults: defaults,
      where: where,
      preload_order: preload_order
    }
  end

  defp get_ref(primary_key, nil, name) when primary_key in [nil, false] do
    raise ArgumentError,
          "need to set :references option for " <>
            "association #{inspect(name)} when schema has no primary key"
  end

  defp get_ref(primary_key, nil, _name), do: elem(primary_key, 0)
  defp get_ref(_primary_key, references, _name), do: references

  @impl true
  def build(%{owner_key: owner_key, related_key: related_key} = refl, owner, attributes) do
    data = refl |> build(owner) |> struct(attributes)
    %{data | related_key => Map.get(owner, owner_key)}
  end

  @impl true
  def joins_query(
        %{related_key: related_key, owner: owner, owner_key: owner_key, queryable: queryable} =
          assoc
      ) do
    from(o in owner, join: q in ^queryable, on: field(q, ^related_key) == field(o, ^owner_key))
    |> Ecto.Association.combine_joins_query(assoc.where, 1)
  end

  @impl true
  def assoc_query(%{related_key: related_key, queryable: queryable} = assoc, query, [value]) do
    from(x in (query || queryable), where: field(x, ^related_key) == ^value)
    |> Ecto.Association.combine_assoc_query(assoc.where)
  end

  @impl true
  def assoc_query(%{related_key: related_key, queryable: queryable} = assoc, query, values) do
    from(x in (query || queryable), where: field(x, ^related_key) in ^values)
    |> Ecto.Association.combine_assoc_query(assoc.where)
  end

  @impl true
  def preload_info(%{related_key: related_key} = refl) do
    {:assoc, refl, {0, related_key}}
  end

  @impl true
  def on_repo_change(
        %{on_replace: :delete_if_exists} = refl,
        parent_changeset,
        %{action: :replace} = changeset,
        adapter,
        opts
      ) do
    try do
      on_repo_change(%{refl | on_replace: :delete}, parent_changeset, changeset, adapter, opts)
    rescue
      Ecto.StaleEntryError -> {:ok, nil}
    end
  end

  def on_repo_change(
        %{on_replace: on_replace} = refl,
        %{data: parent} = parent_changeset,
        %{action: :replace} = changeset,
        adapter,
        opts
      ) do
    changeset =
      case on_replace do
        :nilify -> %{changeset | action: :update}
        :update -> %{changeset | action: :update}
        :delete -> %{changeset | action: :delete}
      end

    changeset = Ecto.Association.update_parent_prefix(changeset, parent)

    case on_repo_change(refl, %{parent_changeset | data: nil}, changeset, adapter, opts) do
      {:ok, _} -> {:ok, nil}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def on_repo_change(assoc, parent_changeset, changeset, _adapter, opts) do
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

  @impl true
  def build(%{related: related, queryable: queryable, defaults: defaults}, owner) do
    related
    |> Ecto.Association.apply_defaults(defaults, owner)
    |> Ecto.Association.merge_source(queryable)
  end

  ## On delete callbacks

  @doc false
  def delete_all(refl, parent, repo_name, opts) do
    if query = on_delete_query(refl, parent) do
      Ecto.Repo.Queryable.delete_all(repo_name, query, opts)
    end
  end

  @doc false
  def nilify_all(%{related_key: related_key} = refl, parent, repo_name, opts) do
    if query = on_delete_query(refl, parent) do
      Ecto.Repo.Queryable.update_all(repo_name, query, [set: [{related_key, nil}]], opts)
    end
  end

  defp on_delete_query(
         %{owner_key: owner_key, related_key: related_key, queryable: queryable},
         parent
       ) do
    if value = Map.get(parent, owner_key) do
      query = from x in queryable, where: field(x, ^related_key) == ^value

      parent
      |> Ecto.get_meta(:prefix)
      |> case do
        nil -> query
        prefix -> Ecto.Query.put_query_prefix(query, prefix)
      end
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
  defstruct [
    :cardinality,
    :field,
    :owner,
    :owner_key,
    :through,
    :on_cast,
    relationship: :child,
    unique: true,
    ordered: false
  ]

  @impl true
  def after_verify_validation(_) do
    :ok
  end

  @impl true
  def struct(module, name, opts) do
    through = Keyword.fetch!(opts, :through)

    refl =
      case through do
        [h, _ | _] ->
          Module.get_attribute(module, :ecto_assocs)[h]

        _ ->
          raise ArgumentError,
                ":through expects a list with at least two entries: " <>
                  "the association in the current module and one step through, got: #{inspect(through)}"
      end

    unless refl do
      raise ArgumentError,
            "schema does not have the association #{inspect(hd(through))} " <>
              "used by association #{inspect(name)}, please ensure the association exists and " <>
              "is defined before the :through one"
    end

    %__MODULE__{
      field: name,
      cardinality: Keyword.fetch!(opts, :cardinality),
      through: through,
      owner: module,
      owner_key: refl.owner_key
    }
  end

  @impl true
  def build(%{field: name}, %{__struct__: owner}, _attributes) do
    raise ArgumentError,
          "cannot build through association `#{inspect(name)}` for #{inspect(owner)}. " <>
            "Instead build the intermediate steps explicitly."
  end

  @impl true
  def preload_info(%{through: through} = refl) do
    {:through, refl, through}
  end

  @impl true
  def on_repo_change(%{field: name}, _, _, _, _) do
    raise ArgumentError,
          "cannot insert/update/delete through associations `#{inspect(name)}` via the repository. " <>
            "Instead build the intermediate steps explicitly."
  end

  @impl true
  def joins_query(%{owner: owner, through: through}) do
    Ecto.Association.join_through_chain(owner, through, from(x in owner))
  end

  @impl true
  def assoc_query(%{owner: owner, through: through}, _, values) do
    Ecto.Association.filter_through_chain(owner, through, values)
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
  @on_replace_opts [:raise, :mark_as_invalid, :delete, :delete_if_exists, :nilify, :update]
  defstruct [
    :field,
    :owner,
    :related,
    :owner_key,
    :related_key,
    :queryable,
    :on_cast,
    :on_replace,
    where: [],
    defaults: [],
    cardinality: :one,
    relationship: :parent,
    unique: true,
    ordered: false
  ]

  @impl true
  def after_verify_validation(%{queryable: queryable, related_key: related_key}) do
    cond do
      not is_atom(queryable) ->
        :ok

      not Code.ensure_loaded?(queryable) ->
        {:error, "associated schema #{inspect(queryable)} does not exist"}

      not function_exported?(queryable, :__schema__, 2) ->
        {:error, "associated module #{inspect(queryable)} is not an Ecto schema"}

      is_nil(queryable.__schema__(:type, related_key)) ->
        {:error, "associated schema #{inspect(queryable)} does not have field `#{related_key}`"}

      true ->
        :ok
    end
  end

  @impl true
  def struct(module, name, opts) do
    ref = if ref = opts[:references], do: ref, else: :id
    queryable = Keyword.fetch!(opts, :queryable)
    related = Ecto.Association.related_from_query(queryable, name)
    on_replace = Keyword.get(opts, :on_replace, :raise)

    unless on_replace in @on_replace_opts do
      raise ArgumentError,
            "invalid `:on_replace` option for #{inspect(name)}. " <>
              "The only valid options are: " <>
              Enum.map_join(@on_replace_opts, ", ", &"`#{inspect(&1)}`")
    end

    defaults = Ecto.Association.validate_defaults!(module, name, opts[:defaults] || [])
    where = opts[:where] || []

    unless is_list(where) do
      raise ArgumentError,
            "expected `:where` for #{inspect(name)} to be a keyword list, got: `#{inspect(where)}`"
    end

    %__MODULE__{
      field: name,
      owner: module,
      related: related,
      owner_key: Keyword.fetch!(opts, :foreign_key),
      related_key: ref,
      queryable: queryable,
      on_replace: on_replace,
      defaults: defaults,
      where: where
    }
  end

  @impl true
  def build(refl, owner, attributes) do
    refl
    |> build(owner)
    |> struct(attributes)
  end

  @impl true
  def joins_query(
        %{related_key: related_key, owner: owner, owner_key: owner_key, queryable: queryable} =
          assoc
      ) do
    from(o in owner, join: q in ^queryable, on: field(q, ^related_key) == field(o, ^owner_key))
    |> Ecto.Association.combine_joins_query(assoc.where, 1)
  end

  @impl true
  def assoc_query(%{related_key: related_key, queryable: queryable} = assoc, query, [value]) do
    from(x in (query || queryable), where: field(x, ^related_key) == ^value)
    |> Ecto.Association.combine_assoc_query(assoc.where)
  end

  @impl true
  def assoc_query(%{related_key: related_key, queryable: queryable} = assoc, query, values) do
    from(x in (query || queryable), where: field(x, ^related_key) in ^values)
    |> Ecto.Association.combine_assoc_query(assoc.where)
  end

  @impl true
  def preload_info(%{related_key: related_key} = refl) do
    {:assoc, refl, {0, related_key}}
  end

  @impl true
  def on_repo_change(%{on_replace: :nilify}, _, %{action: :replace}, _adapter, _opts) do
    {:ok, nil}
  end

  def on_repo_change(
        %{on_replace: :delete_if_exists} = refl,
        parent_changeset,
        %{action: :replace} = changeset,
        adapter,
        opts
      ) do
    try do
      on_repo_change(%{refl | on_replace: :delete}, parent_changeset, changeset, adapter, opts)
    rescue
      Ecto.StaleEntryError -> {:ok, nil}
    end
  end

  def on_repo_change(
        %{on_replace: on_replace} = refl,
        parent_changeset,
        %{action: :replace} = changeset,
        adapter,
        opts
      ) do
    changeset =
      case on_replace do
        :delete -> %{changeset | action: :delete}
        :update -> %{changeset | action: :update}
      end

    on_repo_change(refl, parent_changeset, changeset, adapter, opts)
  end

  def on_repo_change(
        _refl,
        %{data: parent, repo: repo},
        %{action: action} = changeset,
        _adapter,
        opts
      ) do
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

  @impl true
  def build(%{related: related, queryable: queryable, defaults: defaults}, owner) do
    related
    |> Ecto.Association.apply_defaults(defaults, owner)
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
    * `join_defaults` - A list of defaults for join associations
    * `preload_order` - Default `order_by` of the association, used only by preload
  """

  @behaviour Ecto.Association
  @on_delete_opts [:nothing, :delete_all]
  @on_replace_opts [:raise, :mark_as_invalid, :delete]

  defstruct [
    :field,
    :owner,
    :related,
    :owner_key,
    :queryable,
    :on_delete,
    :on_replace,
    :join_keys,
    :join_through,
    :on_cast,
    where: [],
    join_where: [],
    defaults: [],
    join_defaults: [],
    relationship: :child,
    cardinality: :many,
    unique: false,
    ordered: false,
    preload_order: []
  ]

  @impl true
  def after_verify_validation(%{queryable: queryable, join_through: join_through}) do
    cond do
      not is_atom(queryable) ->
        :ok

      not Code.ensure_loaded?(queryable) ->
        {:error, "associated schema #{inspect(queryable)} does not exist"}

      not function_exported?(queryable, :__schema__, 2) ->
        {:error, "associated module #{inspect(queryable)} is not an Ecto schema"}

      not is_atom(join_through) ->
        :ok

      not Code.ensure_loaded?(join_through) ->
        {:error, ":join_through schema #{inspect(join_through)} does not exist"}

      not function_exported?(join_through, :__schema__, 2) ->
        {:error, ":join_through module #{inspect(join_through)} is not an Ecto schema"}

      true ->
        :ok
    end
  end

  @impl true
  def struct(module, name, opts) do
    queryable = Keyword.fetch!(opts, :queryable)
    related = Ecto.Association.related_from_query(queryable, name)

    join_keys = opts[:join_keys]
    join_through = opts[:join_through]
    validate_join_through(name, join_through)

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
                "many_to_many #{inspect(name)} expect :join_keys to be a keyword list " <>
                  "with two entries, the first being how the join table should reach " <>
                  "the current schema and the second how the join table should reach " <>
                  "the associated schema. For example: #{inspect(default_join_keys(module, related))}"
      end

    unless Module.get_attribute(module, :ecto_fields)[owner_key] do
      raise ArgumentError,
            "schema does not have the field #{inspect(owner_key)} used by " <>
              "association #{inspect(name)}, please set the :join_keys option accordingly"
    end

    on_delete = Keyword.get(opts, :on_delete, :nothing)
    on_replace = Keyword.get(opts, :on_replace, :raise)

    unless on_delete in @on_delete_opts do
      raise ArgumentError,
            "invalid :on_delete option for #{inspect(name)}. " <>
              "The only valid options are: " <>
              Enum.map_join(@on_delete_opts, ", ", &"`#{inspect(&1)}`")
    end

    unless on_replace in @on_replace_opts do
      raise ArgumentError,
            "invalid `:on_replace` option for #{inspect(name)}. " <>
              "The only valid options are: " <>
              Enum.map_join(@on_replace_opts, ", ", &"`#{inspect(&1)}`")
    end

    where = opts[:where] || []
    join_where = opts[:join_where] || []
    defaults = Ecto.Association.validate_defaults!(module, name, opts[:defaults] || [])
    join_defaults = Ecto.Association.validate_defaults!(module, name, opts[:join_defaults] || [])
    preload_order = Ecto.Association.validate_preload_order!(name, opts[:preload_order] || [])

    unless is_list(where) do
      raise ArgumentError,
            "expected `:where` for #{inspect(name)} to be a keyword list, got: `#{inspect(where)}`"
    end

    unless is_list(join_where) do
      raise ArgumentError,
            "expected `:join_where` for #{inspect(name)} to be a keyword list, got: `#{inspect(join_where)}`"
    end

    if opts[:join_defaults] && is_binary(join_through) do
      raise ArgumentError, ":join_defaults has no effect for a :join_through without a schema"
    end

    %__MODULE__{
      field: name,
      cardinality: Keyword.fetch!(opts, :cardinality),
      owner: module,
      related: related,
      owner_key: owner_key,
      join_keys: join_keys,
      join_where: join_where,
      join_through: join_through,
      join_defaults: join_defaults,
      queryable: queryable,
      on_delete: on_delete,
      on_replace: on_replace,
      unique: Keyword.get(opts, :unique, false),
      defaults: defaults,
      where: where,
      preload_order: preload_order
    }
  end

  defp default_join_keys(module, related) do
    [
      {Ecto.Association.association_key(module, :id), :id},
      {Ecto.Association.association_key(related, :id), :id}
    ]
  end

  @impl true
  def joins_query(
        %{owner: owner, queryable: queryable, join_through: join_through, join_keys: join_keys} =
          assoc
      ) do
    [{join_owner_key, owner_key}, {join_related_key, related_key}] = join_keys

    from(o in owner,
      join: j in ^join_through,
      on: field(j, ^join_owner_key) == field(o, ^owner_key),
      join: q in ^queryable,
      on: field(j, ^join_related_key) == field(q, ^related_key)
    )
    |> Ecto.Association.combine_joins_query(assoc.where, 2)
    |> Ecto.Association.combine_joins_query(assoc.join_where, 1)
  end

  def assoc_query(%{queryable: queryable} = refl, values) do
    assoc_query(refl, queryable, values)
  end

  @impl true
  def assoc_query(assoc, query, values) do
    %{queryable: queryable, join_through: join_through, join_keys: join_keys, owner: owner} =
      assoc

    [{join_owner_key, owner_key}, {join_related_key, related_key}] = join_keys

    owner_key_type = owner.__schema__(:type, owner_key)

    # We only need to join in the "join table". Preload and Ecto.assoc expressions can then filter
    # by &1.join_owner_key in ^... to filter down to the associated entries in the related table.
    query =
      from(q in (query || queryable),
        join: j in ^join_through,
        on: field(q, ^related_key) == field(j, ^join_related_key),
        where: field(j, ^join_owner_key) in type(^values, {:in, ^owner_key_type})
      )
      |> Ecto.Association.combine_assoc_query(assoc.where)

    Ecto.Association.combine_joins_query(query, assoc.join_where, length(query.joins))
  end

  @impl true
  def build(refl, owner, attributes) do
    refl
    |> build(owner)
    |> struct(attributes)
  end

  @impl true
  def preload_info(%{join_keys: [{join_owner_key, owner_key}, {_, _}], owner: owner} = refl) do
    owner_key_type = owner.__schema__(:type, owner_key)

    # When preloading use the last bound table (which is the join table) and the join_owner_key
    # to filter out related entities to the owner structs we're preloading with.
    {:assoc, refl, {-1, join_owner_key, owner_key_type}}
  end

  @impl true
  def on_repo_change(
        %{on_replace: :delete} = refl,
        parent_changeset,
        %{action: :replace} = changeset,
        adapter,
        opts
      ) do
    on_repo_change(refl, parent_changeset, %{changeset | action: :delete}, adapter, opts)
  end

  def on_repo_change(
        %{join_keys: join_keys, join_through: join_through, join_where: join_where},
        %{repo: repo, data: owner},
        %{action: :delete, data: related},
        adapter,
        opts
      ) do
    [{join_owner_key, owner_key}, {join_related_key, related_key}] = join_keys
    owner_value = dump!(:delete, join_through, owner, owner_key, adapter)
    related_value = dump!(:delete, join_through, related, related_key, adapter)

    query =
      join_through
      |> where([j], field(j, ^join_owner_key) == ^owner_value)
      |> where([j], field(j, ^join_related_key) == ^related_value)
      |> Ecto.Association.combine_assoc_query(join_where)

    query = %{query | prefix: owner.__meta__.prefix}
    repo.delete_all(query, opts)
    {:ok, nil}
  end

  def on_repo_change(
        %{field: field, join_through: join_through, join_keys: join_keys} = refl,
        %{repo: repo, data: owner} = parent_changeset,
        %{action: action} = changeset,
        adapter,
        opts
      ) do
    changeset = Ecto.Association.update_parent_prefix(changeset, owner)

    case apply(repo, action, [changeset, opts]) do
      {:ok, related} ->
        [{join_owner_key, owner_key}, {join_related_key, related_key}] = join_keys

        if insert_join?(parent_changeset, changeset, field, related_key) do
          owner_value = dump!(:insert, join_through, owner, owner_key, adapter)
          related_value = dump!(:insert, join_through, related, related_key, adapter)
          data = %{join_owner_key => owner_value, join_related_key => related_value}

          case insert_join(join_through, refl, parent_changeset, data, opts) do
            {:error, join_changeset} ->
              {:error,
               %{
                 changeset
                 | errors: join_changeset.errors ++ changeset.errors,
                   valid?: join_changeset.valid? and changeset.valid?
               }}

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

  defp validate_join_through(name, nil) do
    raise ArgumentError,
          "many_to_many #{inspect(name)} associations require the :join_through option to be given"
  end

  defp validate_join_through(_, join_through)
       when is_atom(join_through) or is_binary(join_through) do
    :ok
  end

  defp validate_join_through(name, _join_through) do
    raise ArgumentError,
          "many_to_many #{inspect(name)} associations require the :join_through option to be " <>
            "an atom (representing a schema) or a string (representing a table)"
  end

  defp insert_join?(%{action: :insert}, _, _field, _related_key), do: true
  defp insert_join?(_, %{action: :insert}, _field, _related_key), do: true

  defp insert_join?(%{data: owner}, %{data: related}, field, related_key) do
    current_key = Map.fetch!(related, related_key)

    not Enum.any?(Map.fetch!(owner, field), fn child ->
      Map.get(child, related_key) == current_key
    end)
  end

  defp insert_join(join_through, _refl, %{repo: repo, data: owner}, data, opts)
       when is_binary(join_through) do
    opts = Keyword.put_new(opts, :prefix, owner.__meta__.prefix)
    repo.insert_all(join_through, [data], opts)
  end

  defp insert_join(join_through, refl, parent_changeset, data, opts) when is_atom(join_through) do
    %{repo: repo, constraints: constraints, data: owner} = parent_changeset

    changeset =
      join_through
      |> Ecto.Association.apply_defaults(refl.join_defaults, owner)
      |> Map.merge(data)
      |> Ecto.Changeset.change()
      |> Map.put(:constraints, constraints)
      |> put_new_prefix(owner.__meta__.prefix)

    repo.insert(changeset, opts)
  end

  defp put_new_prefix(%{data: %{__meta__: %{prefix: prefix}}} = changeset, prefix),
    do: changeset

  defp put_new_prefix(%{data: %{__meta__: %{prefix: nil}}} = changeset, prefix),
    do: update_in(changeset.data, &Ecto.put_meta(&1, prefix: prefix))

  defp put_new_prefix(changeset, _),
    do: changeset

  defp field!(op, struct, field) do
    Map.get(struct, field) ||
      raise "could not #{op} join entry because `#{field}` is nil in #{inspect(struct)}"
  end

  defp dump!(action, join_through, struct, field, adapter) when is_binary(join_through) do
    value = field!(action, struct, field)
    type = struct.__struct__.__schema__(:type, field)

    case Ecto.Type.adapter_dump(adapter, type, value) do
      {:ok, value} ->
        value

      :error ->
        raise Ecto.ChangeError,
              "value `#{inspect(value)}` for `#{inspect(struct.__struct__)}.#{field}` " <>
                "in `#{action}` does not match type #{Ecto.Type.format(type)}"
    end
  end

  defp dump!(action, join_through, struct, field, _) when is_atom(join_through) do
    field!(action, struct, field)
  end

  ## Relation callbacks
  @behaviour Ecto.Changeset.Relation

  @impl true
  def build(%{related: related, queryable: queryable, defaults: defaults}, owner) do
    related
    |> Ecto.Association.apply_defaults(defaults, owner)
    |> Ecto.Association.merge_source(queryable)
  end

  ## On delete callbacks

  @doc false
  def delete_all(refl, parent, repo_name, opts) do
    %{join_through: join_through, join_keys: join_keys, owner: owner} = refl
    [{join_owner_key, owner_key}, {_, _}] = join_keys

    if value = Map.get(parent, owner_key) do
      owner_type = owner.__schema__(:type, owner_key)

      query =
        from j in join_through, where: field(j, ^join_owner_key) == type(^value, ^owner_type)

      Ecto.Repo.Queryable.delete_all(repo_name, query, opts)
    end
  end
end
