defmodule Ecto.Adapter do
  @moduledoc """
  Specifies the minimal API required from adapters.
  """

  @type t :: module

  @typedoc """
  The metadata returned by the adapter `c:init/1`.

  It must be a map and Ecto itself will always inject
  two keys into the meta:

    * the `:cache` key, which as ETS table that can be used as a cache (if available)
    * the `:pid` key, which is the PID returned by the child spec returned in `c:init/1`

  """
  @type adapter_meta :: map

  @doc """
  The callback invoked in case the adapter needs to inject code.
  """
  @macrocallback __before_compile__(env :: Macro.Env.t()) :: Macro.t()

  @doc """
  Ensure all applications necessary to run the adapter are started.
  """
  @callback ensure_all_started(config :: Keyword.t(), type :: :permanent | :transient | :temporary) ::
              {:ok, [atom]} | {:error, atom}

  @doc """
  Initializes the adapter supervision tree by returning the children and adapter metadata.
  """
  @callback init(config :: Keyword.t()) :: {:ok, :supervisor.child_spec(), adapter_meta}

  @doc """
  Checks out a connection for the duration of the given function.

  In case the adapter provides a pool, this guarantees all of the code
  inside the given `fun` runs against the same connection, which
  might improve performance by for instance allowing multiple related
  calls to the datastore to share cache information:

      Repo.checkout(fn ->
        for _ <- 100 do
          Repo.insert!(%Post{})
        end
      end)

  If the adapter does not provide a pool, just calling the passed function
  and returning its result are enough.

  If the adapter provides a pool, it is supposed to "check out" one of the
  pool connections for the duration of the function call. Which connection
  is checked out is not passed to the calling function, so it should be done
  using a stateful method like using the current process' dictionary, process
  tracking, or some kind of other lookup method. Make sure that this stored
  connection is then used in the other callbacks implementations, such as
  `Ecto.Adapter.Queryable` and `Ecto.Adapter.Schema`.
  """
  @callback checkout(adapter_meta, config :: Keyword.t(), (() -> result)) :: result when result: var

  @doc """
  Returns true if a connection has been checked out.
  """
  @callback checked_out?(adapter_meta) :: boolean

  @doc """
  Returns the loaders for a given type.

  It receives the primitive type and the Ecto type (which may be
  primitive as well). It returns a list of loaders with the given
  type usually at the end.

  This allows developers to properly translate values coming from
  the adapters into Ecto ones. For example, if the database does not
  support booleans but instead returns 0 and 1 for them, you could
  add:

      def loaders(:boolean, type), do: [&bool_decode/1, type]
      def loaders(_primitive, type), do: [type]

      defp bool_decode(0), do: {:ok, false}
      defp bool_decode(1), do: {:ok, true}

  All adapters are required to implement a clause for `:binary_id` types,
  since they are adapter specific. If your adapter does not provide binary
  ids, you may simply use `Ecto.UUID`:

      def loaders(:binary_id, type), do: [Ecto.UUID, type]
      def loaders(_primitive, type), do: [type]

  """
  @callback loaders(primitive_type :: Ecto.Type.primitive(), ecto_type :: Ecto.Type.t()) ::
              [(term -> {:ok, term} | :error) | Ecto.Type.t()]

  @doc """
  Returns the dumpers for a given type.

  It receives the primitive type and the Ecto type (which may be
  primitive as well). It returns a list of dumpers with the given
  type usually at the beginning.

  This allows developers to properly translate values coming from
  the Ecto into adapter ones. For example, if the database does not
  support booleans but instead returns 0 and 1 for them, you could
  add:

      def dumpers(:boolean, type), do: [type, &bool_encode/1]
      def dumpers(_primitive, type), do: [type]

      defp bool_encode(false), do: {:ok, 0}
      defp bool_encode(true), do: {:ok, 1}

  All adapters are required to implement a clause for :binary_id types,
  since they are adapter specific. If your adapter does not provide
  binary ids, you may simply use `Ecto.UUID`:

      def dumpers(:binary_id, type), do: [type, Ecto.UUID]
      def dumpers(_primitive, type), do: [type]

  """
  @callback dumpers(primitive_type :: Ecto.Type.primitive(), ecto_type :: Ecto.Type.t()) ::
              [(term -> {:ok, term} | :error) | Ecto.Type.t()]

  @doc """
  Returns the adapter metadata from the `c:init/1` callback.

  It expects a name or a PID representing a repo.
  """
  def lookup_meta(repo_name_or_pid) do
    {_, meta} = Ecto.Repo.Registry.lookup(repo_name_or_pid)
    meta
  end
end
