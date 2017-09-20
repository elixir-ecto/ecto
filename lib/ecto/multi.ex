defmodule Ecto.Multi do
  @moduledoc """
  `Ecto.Multi` is a data structure for grouping multiple Repo operations.

  `Ecto.Multi` makes it possible to pack operations that should be
  performed in a single database transaction and gives a way to introspect
  the queued operations without actually performing them. Each operation
  is given a name that is unique and will identify its result in case of
  success or failure.

  All operations will be executed in the order they were added.

  The `Ecto.Multi` structure should be considered opaque. You can use
  `%Ecto.Multi{}` to pattern match the type, but accessing fields or
  directly modifying them is not advised.

  `Ecto.Multi.to_list/1` returns a canonical representation of the
  structure that can be used for introspection.

  ## Changesets

  If multi contains operations that accept changesets (like `insert/4`,
  `update/4` or `delete/4`) they will be checked before starting the
  transaction. If any changeset has errors, the transaction won't even
  be started and the error will be immediately returned.

  ## Run

  Multi allows you to run arbitrary functions as part of your transaction
  via `run/3` and `run/5`. This is very useful when an operation depends
  on the value of a previous operation. For this reason, the function given
  as callback to `run/3` and `run/5` will receive all changes performed by
  the multi so far as a map in the first argument.

  The function given to `run` must return `{:ok, value}` or `{:error, value}`
  as its result. Returning an error will abort any further operations
  and make the whole multi fail.

  ## Example

  Let's look at an example definition and usage. The use case we'll be
  looking into is resetting a password. We need to update the account
  with proper information, log the request and remove all current sessions:

      defmodule PasswordManager do
        alias Ecto.Multi

        def reset(account, params) do
          Multi.new
          |> Multi.update(:account, Account.password_reset_changeset(account, params))
          |> Multi.insert(:log, Log.password_reset_changeset(account, params))
          |> Multi.delete_all(:sessions, Ecto.assoc(account, :sessions))
        end
      end

  We can later execute it in the integration layer using Repo:

      Repo.transaction(PasswordManager.reset(account, params))

  By pattern matching on the result we can differentiate different conditions:

      case result do
        {:ok, %{account: account, log: log, sessions: sessions}} ->
          # Operation was successful, we can access results (exactly the same
          # we would get from running corresponding Repo functions) under keys
          # we used for naming the operations.
        {:error, failed_operation, failed_value, changes_so_far} ->
          # One of the operations failed. We can access the operation's failure
          # value (like changeset for operations on changesets) to prepare a
          # proper response. We also get access to the results of any operations
          # that succeeded before the indicated operation failed. However, any
          # successful operations would have been rolled back.
      end

  We can also easily unit test our transaction without actually running it.
  Since changesets can use in-memory-data, we can use an account that is
  constructed in memory as well (without persisting it to the database):

      test "dry run password reset" do
        account = %Account{password: "letmein"}
        multi = PasswordManager.reset(account, params)

        assert [
          {:account, {:update, account_changeset, []}},
          {:log, {:insert, log_changeset, []}},
          {:sessions, {:delete_all, query, []}}
        ] = Ecto.Multi.to_list(multi)

        # We can introspect changesets and query to see if everything
        # is as expected, for example:
        assert account_changeset.valid?
        assert log_changeset.valid?
        assert inspect(query) == "#Ecto.Query<from a in Session>"
      end
  """

  alias __MODULE__
  alias Ecto.Changeset

  defstruct operations: [], names: MapSet.new

  @type run :: (t -> {:ok | :error, any}) | {module, atom, [any]}
  @type merge :: (map -> t) | {module, atom, [any]}
  @typep schema_or_source :: binary | {binary | nil, binary} | atom
  @typep operation :: {:changeset, Changeset.t, Keyword.t} |
                      {:run, run} |
                      {:merge, merge} |
                      {:update_all, Ecto.Query.t, Keyword.t} |
                      {:delete_all, Ecto.Query.t, Keyword.t} |
                      {:insert_all, schema_or_source, [map | Keyword.t], Keyword.t}
  @type name :: any
  @opaque t :: %__MODULE__{operations: [{name, operation}], names: MapSet.t}

  @doc """
  Returns an empty `Ecto.Multi` struct.

  ## Example

      iex> Ecto.Multi.new |> Ecto.Multi.to_list
      []

  """
  @spec new :: t
  def new do
    %Multi{}
  end

  @doc """
  Appends the second multi to the first one.

  All names must be unique between both structures.

  ## Example

      iex> lhs = Ecto.Multi.new |> Ecto.Multi.run(:left, &{:ok, &1})
      iex> rhs = Ecto.Multi.new |> Ecto.Multi.run(:right, &{:error, &1})
      iex> Ecto.Multi.append(lhs, rhs) |> Ecto.Multi.to_list |> Keyword.keys
      [:left, :right]

  """
  @spec append(t, t) :: t
  def append(lhs, rhs) do
    merge_structs(lhs, rhs, &(&2 ++ &1))
  end

  @doc """
  Prepends the second multi to the first one.

  All names must be unique between both structures.

  ## Example

      iex> lhs = Ecto.Multi.new |> Ecto.Multi.run(:left, &{:ok, &1})
      iex> rhs = Ecto.Multi.new |> Ecto.Multi.run(:right, &{:error, &1})
      iex> Ecto.Multi.prepend(lhs, rhs) |> Ecto.Multi.to_list |> Keyword.keys
      [:right, :left]

  """
  @spec prepend(t, t) :: t
  def prepend(lhs, rhs) do
    merge_structs(lhs, rhs, &(&1 ++ &2))
  end

  defp merge_structs(%Multi{} = lhs, %Multi{} = rhs, joiner) do
    %{names: lhs_names, operations: lhs_ops} = lhs
    %{names: rhs_names, operations: rhs_ops} = rhs
    case MapSet.intersection(lhs_names, rhs_names) |> MapSet.to_list do
      [] ->
        %Multi{names: MapSet.union(lhs_names, rhs_names),
               operations: joiner.(lhs_ops, rhs_ops)}
      common ->
        raise ArgumentError, """
        error when merging the following Ecto.Multi structs:

        #{inspect lhs}

        #{inspect rhs}

        both declared operations: #{inspect common}
        """
    end
  end

  @doc """
  Merges a multi returned dynamically by an anonymous function.

  This function is useful when the multi to be merged requires information
  from the original multi. Hence the second argument is an anonymous function
  that receives the multi changes so far. The anonymous function must return
  another multi.

  If you would prefer to simply merge two multis together, see `append/2` or
  `prepend/2`.

  Duplicated operations are not allowed.
  """
  @spec merge(t, (map -> t)) :: t
  def merge(%Multi{} = multi, merge) when is_function(merge, 1) do
    Map.update!(multi, :operations, &[{:merge, {:merge, merge}} | &1])
  end

  @doc """
  Merges a multi returned dynamically by calling `module` and `function` with `args`.

  Similar to `merge/2`, but allows to pass module name, function and arguments.
  The function should return an `Ecto.Multi`, and receives changes so far
  as the first argument (prepended to those passed in the call to the function).

  Duplicated operations are not allowed.
  """
  @spec merge(t, module, function, args) :: t when function: atom, args: [any]
  def merge(%Multi{} = multi, mod, fun, args)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    Map.update!(multi, :operations, &[{:merge, {:merge, {mod, fun, args}}} | &1])
  end

  @doc """
  Adds an insert operation to the multi.

  Accepts the same arguments and options as `c:Ecto.Repo.insert/2` does.
  """
  @spec insert(t, name, Changeset.t | Ecto.Schema.t, Keyword.t) :: t
  def insert(multi, name, changeset_or_struct, opts \\ [])

  def insert(multi, name, %Changeset{} = changeset, opts) do
    add_changeset(multi, :insert, name, changeset, opts)
  end

  def insert(multi, name, struct, opts) do
    insert(multi, name, Changeset.change(struct), opts)
  end

  @doc """
  Adds an update operation to the multi.

  Accepts the same arguments and options as `c:Ecto.Repo.update/2` does.
  """
  @spec update(t, name, Changeset.t, Keyword.t) :: t
  def update(multi, name, %Changeset{} = changeset, opts \\ []) do
    add_changeset(multi, :update, name, changeset, opts)
  end
  
  @doc """
  Inserts or updates a changeset depending on whether the changeset was persisted or not.

  Accepts the same arguments and options as `c:Ecto.Repo.insert_or_update/2` does.
  """
  @spec insert_or_update(t, name, Changeset.t , Keyword.t) :: t
  def insert_or_update(multi, name, changeset, opts \\ [])
  def insert_or_update(multi, name, %Changeset{data: %{__meta__: %{state: :loaded}}} = changeset, opts) do
    add_changeset(multi, :update, name, changeset, opts)
  end
  def insert_or_update(multi, name, %Changeset{} = changeset, opts) do
    add_changeset(multi, :insert, name, changeset, opts)
  end

  @doc """
  Adds a delete operation to the multi.

  Accepts the same arguments and options as `c:Ecto.Repo.delete/2` does.
  """
  @spec delete(t, name, Changeset.t | Ecto.Schema.t, Keyword.t) :: t
  def delete(multi, name, changeset_or_struct, opts \\ [])

  def delete(multi, name, %Changeset{} = changeset, opts) do
    add_changeset(multi, :delete, name, changeset, opts)
  end

  def delete(multi, name, struct, opts) do
    delete(multi, name, Changeset.change(struct), opts)
  end

  defp add_changeset(multi, action, name, changeset, opts) when is_list(opts) do
    add_operation(multi, name, {:changeset, put_action(changeset, action), opts})
  end

  defp put_action(%{action: nil} = changeset, action) do
    %{changeset | action: action}
  end

  defp put_action(%{action: action} = changeset, action) do
    changeset
  end

  defp put_action(%{action: original}, action) do
    raise ArgumentError, "you provided a changeset with an action already set " <>
      "to #{inspect original} when trying to #{action} it"
  end

  @doc """
  Causes the multi to fail with the given value.

  Running the multi in a transaction will execute
  all previous steps until this operation which
  halt with the given `value`.
  """
  @spec error(t, name, error :: term) :: t
  def error(multi, name, value) do
    add_operation(multi, name, {:error, value})
  end

  @doc """
  Adds a function to run as part of the multi.

  The function should return either `{:ok, value}` or `{:error, value}`,
  and receives changes so far as an argument.
  """
  @spec run(t, name, (t -> {:ok | :error, any})) :: t
  def run(multi, name, run) when is_function(run, 1) do
    add_operation(multi, name, {:run, run})
  end

  @doc """
  Adds a function to run as part of the multi.

  Similar to `run/3`, but allows to pass module name, function and arguments.
  The function should return either `{:ok, value}` or `{:error, value}`, and
  will receive changes so far as the first argument (prepended to those passed in
  the call to the function).
  """
  @spec run(t, name, module, function, args) :: t when function: atom, args: [any]
  def run(multi, name, mod, fun, args)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    add_operation(multi, name, {:run, {mod, fun, args}})
  end

  @doc """
  Adds an insert_all operation to the multi.

  Accepts the same arguments and options as `c:Ecto.Repo.insert_all/3` does.
  """
  @spec insert_all(t, name, schema_or_source, [entry], Keyword.t) :: t
        when entry: map | Keyword.t
  def insert_all(multi, name, schema_or_source, entries, opts \\ []) when is_list(opts) do
    add_operation(multi, name, {:insert_all, schema_or_source, entries, opts})
  end

  @doc """
  Adds an update_all operation to the multi.

  Accepts the same arguments and options as `c:Ecto.Repo.update_all/3` does.
  """
  @spec update_all(t, name, Ecto.Queryable.t, Keyword.t, Keyword.t) :: t
  def update_all(multi, name, queryable, updates, opts \\ []) when is_list(opts) do
    query = Ecto.Queryable.to_query(queryable)
    add_operation(multi, name, {:update_all, query, updates, opts})
  end

  @doc """
  Adds a delete_all operation to the multi.

  Accepts the same arguments and options as `c:Ecto.Repo.delete_all/2` does.
  """
  @spec delete_all(t, name, Ecto.Queryable.t, Keyword.t) :: t
  def delete_all(multi, name, queryable, opts \\ []) when is_list(opts) do
    query = Ecto.Queryable.to_query(queryable)
    add_operation(multi, name, {:delete_all, query, opts})
  end

  defp add_operation(%Multi{} = multi, name, operation) do
    %{operations: operations, names: names} = multi
    if MapSet.member?(names, name) do
      raise "#{inspect name} is already a member of the Ecto.Multi: \n#{inspect multi}"
    else
      %{multi | operations: [{name, operation} | operations],
                names: MapSet.put(names, name)}
    end
  end

  @doc """
  Returns the list of operations stored in `multi`.

  Always use this function when you need to access the operations you
  have defined in `Ecto.Multi`. Inspecting the `Ecto.Multi` struct internals
  directly is discouraged.
  """
  @spec to_list(t) :: [{name, term}]
  def to_list(%Multi{operations: operations}) do
    operations
    |> Enum.reverse
    |> Enum.map(&format_operation/1)
  end

  defp format_operation({name, {:changeset, changeset, opts}}),
    do: {name, {changeset.action, changeset, opts}}
  defp format_operation(other),
    do: other

  @doc false
  @spec __apply__(t, Ecto.Repo.t, fun, (term -> no_return)) :: {:ok, term} | {:error, term}
  def __apply__(%Multi{} = multi, repo, wrap, return) do
    multi.operations
    |> Enum.reverse
    |> check_operations_valid
    |> apply_operations(multi.names, repo, wrap, return)
  end

  defp check_operations_valid(operations) do
    Enum.find_value(operations, &invalid_operation/1) || {:ok, operations}
  end

  defp invalid_operation({name, {:changeset, %{valid?: false} = changeset, _}}),
    do: {:error, {name, changeset, %{}}}
  defp invalid_operation(_operation),
    do: nil

  defp apply_operations({:ok, []}, _names, _repo, _wrap, _return), do: {:ok, %{}}
  defp apply_operations({:ok, operations}, names, repo, wrap, return) do
    wrap.(fn ->
      operations
      |> Enum.reduce({%{}, names}, &apply_operation(&1, repo, wrap, return, &2))
      |> elem(0)
    end)
  end

  defp apply_operations({:error, error}, _names, _repo, _wrap, _return) do
    {:error, error}
  end

  defp apply_operation({name, operation}, repo, wrap, return, {acc, names}) do
    case apply_operation(operation, acc, {wrap, return}, repo) do
      {:merge, {:ok, value}} ->
        merge_results(acc, value, names)
      {:merge, {:error, {name, value, nested_acc}}} ->
        {acc, _names} = merge_results(acc, nested_acc, names)
        return.({name, value, acc})
      {:ok, value} ->
        {Map.put(acc, name, value), names}
      {:error, value} ->
        return.({name, value, acc})
    end
  end

  defp apply_operation({:changeset, changeset, opts}, _acc, _apply_args, repo),
    do: apply(repo, changeset.action, [changeset, opts])
  defp apply_operation({:run, run}, acc, _apply_args, _repo),
    do: apply_fun(run, acc)
  defp apply_operation({:error, value}, _acc, _apply_args, _repo),
    do: {:error, value}
  defp apply_operation({:insert_all, source, entries, opts}, _acc, _apply_args, repo),
    do: {:ok, repo.insert_all(source, entries, opts)}
  defp apply_operation({:update_all, query, updates, opts}, _acc, _apply_args, repo),
    do: {:ok, repo.update_all(query, updates, opts)}
  defp apply_operation({:delete_all, query, opts}, _acc, _apply_args, repo),
    do: {:ok, repo.delete_all(query, opts)}
  defp apply_operation({:merge, merge}, acc, {wrap, return}, repo),
    do: {:merge, __apply__(apply_fun(merge, acc), repo, wrap, return)}

  defp apply_fun({mod, fun, args}, acc), do: apply(mod, fun, [acc | args])
  defp apply_fun(fun, acc),              do: apply(fun, [acc])

  defp merge_results(changes, new_changes, names) do
    new_names = new_changes |> Map.keys |> MapSet.new
    case MapSet.intersection(names, new_names) |> MapSet.to_list do
      [] ->
        {Map.merge(changes, new_changes), MapSet.union(names, new_names)}
      common ->
        raise "cannot merge multi, the following operations were found in " <>
          "both Ecto.Multi: #{inspect common}"
    end
  end
end
