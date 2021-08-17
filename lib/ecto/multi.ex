defmodule Ecto.Multi do
  @moduledoc """
  `Ecto.Multi` is a data structure for grouping multiple Repo operations.

  `Ecto.Multi` makes it possible to pack operations that should be
  performed in a single database transaction and gives a way to introspect
  the queued operations without actually performing them. Each operation
  is given a name that is unique and will identify its result in case of
  success or failure.

  If a multi is valid (i.e. all the changesets in it are valid),
  all operations will be executed in the order they were added.

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

  Note: `insert/4`, `update/4`, `insert_or_update/4`, and `delete/4`
  variants that accept a function are not performing such checks since
  the functions are executed after the transaction has started.

  ## Run

  Multi allows you to run arbitrary functions as part of your transaction
  via `run/3` and `run/5`. This is especially useful when an operation
  depends on the value of a previous operation. For this reason, the
  function given as a callback to `run/3` and `run/5` will receive the repo
  as the first argument, and all changes performed by the multi so far as a
  map for the second argument.

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
          Multi.new()
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

  The name of each operation does not have to be an atom. This can be particularly
  useful when you wish to update a collection of changesets at once, and track their
  errors individually:

      accounts = [%Account{id: 1}, %Account{id: 2}]

      Enum.reduce(accounts, Multi.new(), fn account, multi ->
        Multi.update(
          multi,
          {:account, account.id},
          Account.password_reset_changeset(account, params)
        )
      end)
  """

  alias __MODULE__
  alias Ecto.Changeset

  defstruct operations: [], names: MapSet.new()

  @type changes :: map
  @type run :: ((Ecto.Repo.t, changes) -> {:ok | :error, any}) | {module, atom, [any]}
  @type fun(result) :: (changes -> result)
  @type merge :: (changes -> t) | {module, atom, [any]}
  @typep schema_or_source :: binary | {binary, module} | module
  @typep operation :: {:changeset, Changeset.t, Keyword.t} |
                      {:run, run} |
                      {:put, any} |
                      {:inspect, Keyword.t} |
                      {:merge, merge} |
                      {:update_all, Ecto.Query.t, Keyword.t} |
                      {:delete_all, Ecto.Query.t, Keyword.t} |
                      {:insert_all, schema_or_source, [map | Keyword.t], Keyword.t}
  @typep operations :: [{name, operation}]
  @typep names :: MapSet.t
  @type name :: any
  @type t :: %__MODULE__{operations: operations, names: names}

  @doc """
  Returns an empty `Ecto.Multi` struct.

  ## Example

      iex> Ecto.Multi.new() |> Ecto.Multi.to_list()
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

      iex> lhs = Ecto.Multi.new() |> Ecto.Multi.run(:left, fn _, changes -> {:ok, changes} end)
      iex> rhs = Ecto.Multi.new() |> Ecto.Multi.run(:right, fn _, changes -> {:error, changes} end)
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

      iex> lhs = Ecto.Multi.new() |> Ecto.Multi.run(:left, fn _, changes -> {:ok, changes} end)
      iex> rhs = Ecto.Multi.new() |> Ecto.Multi.run(:right, fn _, changes -> {:error, changes} end)
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

        #{Kernel.inspect lhs}

        #{Kernel.inspect rhs}

        both declared operations: #{Kernel.inspect common}
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

  ## Example

      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:post, %Post{title: "first"})

      multi
      |> Ecto.Multi.merge(fn %{post: post} ->
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:comment, Ecto.build_assoc(post, :comments))
      end)
      |> MyApp.Repo.transaction()
  """
  @spec merge(t, (changes -> t)) :: t
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

  ## Example

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:insert, %Post{title: "first"})
      |> MyApp.Repo.transaction()

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:post, %Post{title: "first"})
      |> Ecto.Multi.insert(:comment, fn %{post: post} ->
           Ecto.build_assoc(post, :comments)
         end)
      |> MyApp.Repo.transaction()

  """
  @spec insert(t, name, Changeset.t | Ecto.Schema.t | fun(Changeset.t | Ecto.Schema.t), Keyword.t) :: t
  def insert(multi, name, changeset_or_struct_or_fun, opts \\ [])

  def insert(multi, name, %Changeset{} = changeset, opts) do
    add_changeset(multi, :insert, name, changeset, opts)
  end

  def insert(multi, name, %_{} = struct, opts) do
    insert(multi, name, Changeset.change(struct), opts)
  end

  def insert(multi, name, fun, opts) when is_function(fun, 1) do
    run(multi, name, operation_fun({:insert, fun}, opts))
  end

  @doc """
  Adds an update operation to the multi.

  Accepts the same arguments and options as `c:Ecto.Repo.update/2` does.

  ## Example

      post = MyApp.Repo.get!(Post, 1)
      changeset = Ecto.Changeset.change(post, title: "New title")
      Ecto.Multi.new()
      |> Ecto.Multi.update(:update, changeset)
      |> MyApp.Repo.transaction()

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:post, %Post{title: "first"})
      |> Ecto.Multi.update(:fun, fn %{post: post} ->
           Ecto.Changeset.change(post, title: "New title")
         end)
      |> MyApp.Repo.transaction()

  """
  @spec update(t, name, Changeset.t | fun(Changeset.t), Keyword.t) :: t
  def update(multi, name, changeset_or_fun, opts \\ [])

  def update(multi, name, %Changeset{} = changeset, opts) do
    add_changeset(multi, :update, name, changeset, opts)
  end

  def update(multi, name, fun, opts) when is_function(fun, 1) do
    run(multi, name, operation_fun({:update, fun}, opts))
  end

  @doc """
  Inserts or updates a changeset depending on whether the changeset was persisted or not.

  Accepts the same arguments and options as `c:Ecto.Repo.insert_or_update/2` does.

  ## Example

      changeset = Post.changeset(%Post{}, %{title: "New title"})
      Ecto.Multi.new()
      |> Ecto.Multi.insert_or_update(:insert_or_update, changeset)
      |> MyApp.Repo.transaction()

      Ecto.Multi.new()
      |> Ecto.Multi.run(:post, fn repo, _changes ->
           {:ok, repo.get(Post, 1) || %Post{}}
         end)
      |> Ecto.Multi.insert_or_update(:update, fn %{post: post} ->
           Ecto.Changeset.change(post, title: "New title")
         end)
      |> MyApp.Repo.transaction()

  """
  @spec insert_or_update(t, name, Changeset.t | fun(Changeset.t), Keyword.t) :: t
  def insert_or_update(multi, name, changeset_or_fun, opts \\ [])

  def insert_or_update(multi, name, %Changeset{data: %{__meta__: %{state: :loaded}}} = changeset, opts) do
    add_changeset(multi, :update, name, changeset, opts)
  end

  def insert_or_update(multi, name, %Changeset{} = changeset, opts) do
    add_changeset(multi, :insert, name, changeset, opts)
  end

  def insert_or_update(multi, name, fun, opts) when is_function(fun, 1) do
    run(multi, name, operation_fun({:insert_or_update, fun}, opts))
  end

  @doc """
  Adds a delete operation to the multi.

  Accepts the same arguments and options as `c:Ecto.Repo.delete/2` does.

  ## Example

      post = MyApp.Repo.get!(Post, 1)
      Ecto.Multi.new()
      |> Ecto.Multi.delete(:delete, post)
      |> MyApp.Repo.transaction()

      Ecto.Multi.new()
      |> Ecto.Multi.run(:post, fn repo, _changes ->
           case repo.get(Post, 1) do
             nil -> {:error, :not_found}
             post -> {:ok, post}
           end
         end)
      |> Ecto.Multi.delete(:delete, fn %{post: post} ->
           # Others validations
           post
         end)
      |> MyApp.Repo.transaction()

  """
  @spec delete(t, name, Changeset.t | Ecto.Schema.t | fun(Changeset.t | Ecto.Schema.t), Keyword.t) :: t
  def delete(multi, name, changeset_or_struct_fun, opts \\ [])

  def delete(multi, name, %Changeset{} = changeset, opts) do
    add_changeset(multi, :delete, name, changeset, opts)
  end

  def delete(multi, name, %_{} = struct, opts) do
    delete(multi, name, Changeset.change(struct), opts)
  end

  def delete(multi, name, fun, opts) when is_function(fun, 1) do
    run(multi, name, operation_fun({:delete, fun}, opts))
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
      "to #{Kernel.inspect original} when trying to #{action} it"
  end

  @doc """
  Causes the multi to fail with the given value.

  Running the multi in a transaction will execute
  no previous steps and returns the value of the first
  error added.
  """
  @spec error(t, name, error :: term) :: t
  def error(multi, name, value) do
    add_operation(multi, name, {:error, value})
  end

  @doc """
  Adds a function to run as part of the multi.

  The function should return either `{:ok, value}` or `{:error, value}`,
  and receives the repo as the first argument, and the changes so far
  as the second argument.

  ## Example

      Ecto.Multi.run(multi, :write, fn _repo, %{image: image} ->
        with :ok <- File.write(image.name, image.contents) do
          {:ok, nil}
        end
      end)
  """
  @spec run(t, name, run) :: t
  def run(multi, name, run) when is_function(run, 2) do
    add_operation(multi, name, {:run, run})
  end

  @doc """
  Adds a function to run as part of the multi.

  Similar to `run/3`, but allows to pass module name, function and arguments.
  The function should return either `{:ok, value}` or `{:error, value}`, and
  receives the repo as the first argument, and the changes so far as the
  second argument (prepended to those passed in the call to the function).
  """
  @spec run(t, name, module, function, args) :: t when function: atom, args: [any]
  def run(multi, name, mod, fun, args)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    add_operation(multi, name, {:run, {mod, fun, args}})
  end

  @doc """
  Adds an insert_all operation to the multi.

  Accepts the same arguments and options as `c:Ecto.Repo.insert_all/3` does.

  ## Example

      posts = [%{title: "My first post"}, %{title: "My second post"}]
      Ecto.Multi.new()
      |> Ecto.Multi.insert_all(:insert_all, Post, posts)
      |> MyApp.Repo.transaction()

      Ecto.Multi.new()
      |> Ecto.Multi.run(:post, fn repo, _changes ->
        case repo.get(Post, 1) do
          nil -> {:error, :not_found}
          post -> {:ok, post}
        end
      end)
      |> Ecto.Multi.insert_all(:insert_all, Comment, fn %{post: post} ->
        # Others validations

        entries
        |> Enum.map(fn comment ->
          Map.put(comment, :post_id, post.id)
        end)
      end)
      |> MyApp.Repo.transaction()

  """
  @spec insert_all(t, name, schema_or_source, [map | Keyword.t] | fun([map | Keyword.t]), Keyword.t) :: t
  def insert_all(multi, name, schema_or_source, entries_or_fun, opts \\ [])

  def insert_all(multi, name, schema_or_source, entries_fun, opts) when is_function(entries_fun, 1) and is_list(opts) do
    run(multi, name, operation_fun({:insert_all, schema_or_source, entries_fun}, opts))
  end

  def insert_all(multi, name, schema_or_source, entries, opts) when is_list(opts) do
    add_operation(multi, name, {:insert_all, schema_or_source, entries, opts})
  end

  @doc """
  Adds an update_all operation to the multi.

  Accepts the same arguments and options as `c:Ecto.Repo.update_all/3` does.

  ## Example

      Ecto.Multi.new()
      |> Ecto.Multi.update_all(:update_all, Post, set: [title: "New title"])
      |> MyApp.Repo.transaction()

      Ecto.Multi.new()
      |> Ecto.Multi.run(:post, fn repo, _changes ->
        case repo.get(Post, 1) do
          nil -> {:error, :not_found}
          post -> {:ok, post}
        end
      end)
      |> Ecto.Multi.update_all(:update_all, fn %{post: post} ->
        # Others validations
        from(c in Comment, where: c.post_id == ^post.id, update: [set: [title: "New title"]])
      end, [])
      |> MyApp.Repo.transaction()

  """
  @spec update_all(t, name, Ecto.Queryable.t | fun(Ecto.Queryable.t), Keyword.t, Keyword.t) :: t
  def update_all(multi, name, queryable_or_fun, updates, opts \\ [])

  def update_all(multi, name, queryable_fun, updates, opts) when is_function(queryable_fun, 1) and is_list(opts) do
    run(multi, name, operation_fun({:update_all, queryable_fun, updates}, opts))
  end

  def update_all(multi, name, queryable, updates, opts) when is_list(opts) do
    query = Ecto.Queryable.to_query(queryable)
    add_operation(multi, name, {:update_all, query, updates, opts})
  end

  @doc """
  Adds a delete_all operation to the multi.

  Accepts the same arguments and options as `c:Ecto.Repo.delete_all/2` does.

  ## Example

      queryable = from(p in Post, where: p.id < 5)
      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(:delete_all, queryable)
      |> MyApp.Repo.transaction()

      Ecto.Multi.new()
      |> Ecto.Multi.run(:post, fn repo, _changes ->
        case repo.get(Post, 1) do
          nil -> {:error, :not_found}
          post -> {:ok, post}
        end
      end)
      |> Ecto.Multi.delete_all(:delete_all, fn %{post: post} ->
        # Others validations
        from(c in Comment, where: c.post_id == ^post.id)
      end)
      |> MyApp.Repo.transaction()

  """
  @spec delete_all(t, name, Ecto.Queryable.t | fun(Ecto.Queryable.t), Keyword.t) :: t
  def delete_all(multi, name, queryable_or_fun, opts \\ [])

  def delete_all(multi, name, fun, opts) when is_function(fun, 1) and is_list(opts) do
    run(multi, name, operation_fun({:delete_all, fun}, opts))
  end

  def delete_all(multi, name, queryable, opts) when is_list(opts) do
    query = Ecto.Queryable.to_query(queryable)
    add_operation(multi, name, {:delete_all, query, opts})
  end

  defp add_operation(%Multi{} = multi, name, operation) do
    %{operations: operations, names: names} = multi
    if MapSet.member?(names, name) do
      raise "#{Kernel.inspect name} is already a member of the Ecto.Multi: \n#{Kernel.inspect multi}"
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

  @doc """
  Adds a value to the changes so far under the given name.

  ## Example

      Ecto.Multi.new()
      |> Ecto.Multi.put(:params, params)
      |> Ecto.Multi.insert(:user, fn changes -> User.changeset(changes.params) end)
      |> Ecto.Multi.insert(:person, fn changes -> Person.changeset(changes.user, changes.params) end)
      |> MyApp.Repo.transaction()
  """
  @spec put(t, name, any) :: t
  def put(multi, name, value) do
    add_operation(multi, name, {:put, value})
  end

  @doc """
  Inspects results from a Multi

  By default, the name is shown as a label to the inspect, custom labels are
  supported through the `IO.inspect/2` `label` option.

  ## Options

  All options for IO.inspect/2 are supported, it also support the following ones:

    * `:only` - A field or a list of fields to inspect, will print the entire
      map by default.

  ## Examples

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:person_a, changeset)
      |> Ecto.Multi.insert(:person_b, changeset)
      |> Ecto.Multi.inspect()
      |> MyApp.Repo.transaction()

  Prints:
      %{person_a: %Person{...}, person_b: %Person{...}}

  We can use the `:only` option to limit which fields will be printed:

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:person_a, changeset)
      |> Ecto.Multi.insert(:person_b, changeset)
      |> Ecto.Multi.inspect(only: :person_a)
      |> MyApp.Repo.transaction()

  Prints:
      %{person_a: %Person{...}}

  """
  @spec inspect(t, Keyword.t) :: t
  def inspect(multi, opts \\ []) do
    Map.update!(multi, :operations, &[{:inspect, {:inspect, opts}} | &1])
  end

  @doc false
  @spec __apply__(t, Ecto.Repo.t, fun, (term -> no_return)) :: {:ok, term} | {:error, term}
  def __apply__(%Multi{} = multi, repo, wrap, return) do
    operations = Enum.reverse(multi.operations)

    with {:ok, operations} <- check_operations_valid(operations) do
      apply_operations(operations, multi.names, repo, wrap, return)
    end
  end

  defp check_operations_valid(operations) do
    Enum.find_value(operations, &invalid_operation/1) || {:ok, operations}
  end

  defp invalid_operation({name, {:changeset, %{valid?: false} = changeset, _}}),
    do: {:error, {name, changeset, %{}}}
  defp invalid_operation({name, {:error, value}}),
    do: {:error, {name, value, %{}}}
  defp invalid_operation(_operation),
    do: nil

  defp apply_operations([], _names, _repo, _wrap, _return), do: {:ok, %{}}
  defp apply_operations(operations, names, repo, wrap, return) do
    wrap.(fn ->
      operations
      |> Enum.reduce({%{}, names}, &apply_operation(&1, repo, wrap, return, &2))
      |> elem(0)
    end)
  end

  defp apply_operation({_, {:merge, merge}}, repo, wrap, return, {acc, names}) do
    case __apply__(apply_merge_fun(merge, acc), repo, wrap, return) do
      {:ok, value} ->
        merge_results(acc, value, names)
      {:error, {name, value, nested_acc}} ->
        {acc, _names} = merge_results(acc, nested_acc, names)
        return.({name, value, acc})
    end
  end

  defp apply_operation({_name, {:inspect, opts}}, _repo, _wrap_, _return, {acc, names}) do
    if opts[:only] do
      acc |> Map.take(List.wrap(opts[:only])) |> IO.inspect(opts)
    else
      IO.inspect(acc, opts)
    end

    {acc, names}
  end

  defp apply_operation({name, operation}, repo, wrap, return, {acc, names}) do
    case apply_operation(operation, acc, {wrap, return}, repo) do
      {:ok, value} ->
        {Map.put(acc, name, value), names}
      {:error, value} ->
        return.({name, value, acc})
      other ->
        raise "expected Ecto.Multi callback named `#{Kernel.inspect name}` to return either {:ok, value} or {:error, value}, got: #{Kernel.inspect other}"
    end
  end

  defp apply_operation({:changeset, changeset, opts}, _acc, _apply_args, repo),
    do: apply(repo, changeset.action, [changeset, opts])
  defp apply_operation({:run, run}, acc, _apply_args, repo),
    do: apply_run_fun(run, repo, acc)
  defp apply_operation({:error, value}, _acc, _apply_args, _repo),
    do: {:error, value}
  defp apply_operation({:insert_all, source, entries, opts}, _acc, _apply_args, repo),
    do: {:ok, repo.insert_all(source, entries, opts)}
  defp apply_operation({:update_all, query, updates, opts}, _acc, _apply_args, repo),
    do: {:ok, repo.update_all(query, updates, opts)}
  defp apply_operation({:delete_all, query, opts}, _acc, _apply_args, repo),
    do: {:ok, repo.delete_all(query, opts)}
  defp apply_operation({:put, value}, _acc, _apply_args, _repo),
    do: {:ok, value}

  defp apply_merge_fun({mod, fun, args}, acc), do: apply(mod, fun, [acc | args])
  defp apply_merge_fun(fun, acc), do: apply(fun, [acc])

  defp apply_run_fun({mod, fun, args}, repo, acc), do: apply(mod, fun, [repo, acc | args])
  defp apply_run_fun(fun, repo, acc), do: apply(fun, [repo, acc])

  defp merge_results(changes, new_changes, names) do
    new_names = new_changes |> Map.keys |> MapSet.new()
    case MapSet.intersection(names, new_names) |> MapSet.to_list do
      [] ->
        {Map.merge(changes, new_changes), MapSet.union(names, new_names)}
      common ->
        raise "cannot merge multi, the following operations were found in " <>
          "both Ecto.Multi: #{Kernel.inspect common}"
    end
  end

  defp operation_fun({:update_all, queryable_fun, updates}, opts) do
    fn repo, changes ->
      {:ok, repo.update_all(queryable_fun.(changes), updates, opts)}
    end
  end

  defp operation_fun({:insert_all, schema_or_source, entries_fun}, opts) do
    fn repo, changes ->
      {:ok, repo.insert_all(schema_or_source, entries_fun.(changes), opts)}
    end
  end

  defp operation_fun({:delete_all, fun}, opts) do
    fn repo, changes ->
      {:ok, repo.delete_all(fun.(changes), opts)}
    end
  end

  defp operation_fun({operation, fun}, opts) do
    fn repo, changes ->
      apply(repo, operation, [fun.(changes), opts])
    end
  end
end
