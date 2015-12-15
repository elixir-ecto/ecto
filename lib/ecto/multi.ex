defmodule Ecto.Multi do
  alias __MODULE__
  alias Ecto.Changeset

  defstruct operations: [], names: MapSet.new

  @type run :: (t, Keyword.t -> {:ok | :error, any})
  @type operation :: Changeset.t | run
  @type name :: atom
  @type t :: %__MODULE__{operations: [{name, operation}]}

  @spec new :: t
  def new do
    %Multi{}
  end

  @spec insert(t, name, Changeset.t | Model.t) :: t
  def insert(multi, name, %Changeset{} = changeset) do
    add_changeset(multi, :insert, name, changeset)
  end

  def insert(multi, name, struct) do
    add_changeset(multi, :insert, name, Changeset.change(struct))
  end

  @spec update(t, name, Changeset.t) :: t
  def update(multi, name, %Changeset{} = changeset) do
    add_changeset(multi, :update, name, changeset)
  end

  @spec delete(t, name, Changeset.t | Model.t) :: t
  def delete(multi, name, %Changeset{} = changeset) do
    add_changeset(multi, :delete, name, changeset)
  end

  def delete(multi, name, struct) do
    add_changeset(multi, :delete, name, Changeset.change(struct))
  end

  defp add_changeset(multi, action, name, changeset) do
    add_operation(multi, name, put_action(changeset, action))
  end

  defp put_action(%{action: nil} = changeset, action) do
    %{changeset | action: action}
  end

  defp put_action(%{action: action} = changeset, action) do
    changeset
  end

  defp put_action(%{action: original}, action) do
    raise ArgumentError, "you provided a changeset with an action already set " <>
      "to #{original} when trying to #{action} it"
  end

  @spec run(t, name, run) :: t
  def run(multi, name, run) when is_function(run, 2) do
    add_operation(multi, name, run)
  end

  @spec run(t, name, module, function, args) :: t
    when function: atom, args: [any]
  def run(multi, name, mod, fun, args) do
    add_operation(multi, name, {mod, fun, args})
  end

  defp add_operation(%Multi{operations: operations, names: names} = multi, name, operation)
      when is_atom(name) do
    if MapSet.member?(names, name) do
      raise "#{name} is already a member of the Ecto.Multi: \n#{inspect multi}"
    else
      %{multi | operations: [{name, operation} | operations],
                names: MapSet.put(names, name)}
    end
  end

  @spec apply(t, Ecto.Repo.t, wrap, return, Keyword.t) ::
      {:ok, results} | {:error, {name, errors}}
    when results: %{name => Ecto.Schema.t | any},
         errors: %{name => Changeset.t | :skipped | any},
         wrap: ((() -> any), Keyword.t -> {:ok | :error, any}),
         return: (any -> no_return)
  def apply(%Multi{} = multi, repo, wrap, return, opts \\ []) do
    # TODO skip transaction if changesets are invalid
    multi.operations
    |> Enum.reverse
    |> apply_operations(repo, wrap, return, opts)
  end

  defp apply_operations(operations, repo, wrap, return, opts) do
    wrap.(opts, fn ->
      do_apply_operations(operations, repo, return, opts, %{})
    end)
  end

  defp do_apply_operations([], _repo, _return, _opts, acc) do
    acc
  end

  defp do_apply_operations([{name, operation} | rest], repo, return, opts, acc) do
    case apply_operation(operation, acc, repo, opts) do
      {:ok, value} ->
        do_apply_operations(rest, repo, return, opts, Map.put(acc, name, value))
      {:error, value} ->
        return.(%{name => value})
    end
  end

  defp apply_operation(%Changeset{action: action} = changeset, _acc, repo, opts) do
    apply(repo, action, [changeset, opts])
  end

  defp apply_operation(run, acc, _repo, opts) when is_function(run, 2) do
    apply(run, [acc, opts])
  end

  defp apply_operation({mod, fun, args}, acc, _repo, opts) do
    apply(mod, fun, [acc, opts | args])
  end
end
