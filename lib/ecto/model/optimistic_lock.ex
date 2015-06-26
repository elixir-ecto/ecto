defmodule Ecto.Model.OptimisticLock do
  @moduledoc """
  Facilities for using the optimistic-locking technique.

  [Optimistic
  locking](http://en.wikipedia.org/wiki/Optimistic_concurrency_control) (or
  *optimistic concurrency control*) is a technique that allows concurrent edits
  on a single record. While pessimistic locking works by locking a resource for
  an entire transaction, optimistic locking only checks if the resource changed
  before updating it.

  This is done by regularly fetching the record from the database, then checking
  whether another process has made changes to the record *only when updating the
  record*. This behaviour is ideal in situations where the chances of concurrent
  updates to the same record are low; if they're not, pessimistic locking or
  other concurrency patterns may be more suited.

  ## Usage

  Optimistic locking works by keeping a "version" counter for each record; this
  counter gets incremented each time a modification is made to a record. Hence,
  in order to use optimistic locking, a column must be added to a given model's
  table and a field must be added to that model's schema.

  ## Examples

  Assuming we have a `Post` model (stored in the `posts` table), the first step
  is to add a version column to the `posts` table:

      alter table(:posts) do
        add :lock_version, :integer, default: 1
      end

  The column name is arbitrary and doesn't need to be `:lock_version`. However,
  it **needs to be an integer**.

  Now a field must be added to the schema and the `optimistic_lock/1` macro has
  to be used in order to specify which column in the schema will be used as
  the "version" column.

      defmodule Post do
        use Ecto.Model

        schema "posts" do
          field :title, :string
          field :lock_version, :integer, default: 1
        end

        optimistic_lock :lock_version
      end

  Note that the `optimistic_lock/1` macro is defined in this module, which is
  imported when `Ecto.Model` is used. To use the `optimistic_lock/1` macro
  without using `Ecto.Model`, just use `Ecto.Model.OptimisticLock` but be sure
  to use `Ecto.Model.Callbacks` as well since it's used by
  `Ecto.Model.OptimisticLock` under the hood.

  When a conflict happens (a record which has been previously fetched is being
  updated, but that same record has been modified since it was fetched), an
  `Ecto.StaleModelError` exception is raised.

      iex> post = Repo.insert!(%Post{title: "foo"})
      %Post{id: 1, title: "foo", lock_version: 1}
      iex> valid_change = cast(%{title: "bar"}, post, ~w(title), ~w())
      iex> stale_change = cast(%{title: "baz"}, post, ~w(title), ~w())
      iex> Repo.update!(valid_change)
      %Post{id: 1, title: "bar", lock_version: 2}
      iex> Repo.update!(stale_change)
      ** (Ecto.StaleModelError) attempted to update a stale model:

      %Post{id: 1, title: "baz", lock_version: 1}

  Optimistic locking also works with delete operations: when trying to delete a
  stale model, an `Ecto.StaleModelError` exception is raised as well.
  """

  import Ecto.Changeset

  @doc false
  defmacro __using__(_) do
    quote do
      import Ecto.Model.OptimisticLock
    end
  end

  @doc """
  Specifies a field to use with optimistic locking.

  This macro specifies a `field` that will be used to implement the
  optimistic-locking technique described in the docs for this module.

  `optimistic_lock/1` can be used multiple times per model.

  ## Examples

      defmodule Note do
        use Ecto.Model

        schema "notes" do
          add :title, :string
          add :body, :text
          add :optlock, :integer, default: 1
        end

        optimistic_lock :optlock
      end

  """
  defmacro optimistic_lock(field) do
    quote bind_quoted: [field: field] do
      before_update Ecto.Model.OptimisticLock, :__lock__, [field]
      before_delete Ecto.Model.OptimisticLock, :__lock__, [field]
    end
  end

  @doc false
  def __lock__(%Ecto.Changeset{model: model} = changeset, field) do
    current = Map.fetch!(model, field)
    update_in(changeset.filters, &Map.put(&1, field, current))
    |> force_change(field, current + 1)
  end
end
