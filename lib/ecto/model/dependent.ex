defmodule Ecto.Model.Dependent do
  @moduledoc """
  Defines callbacks for handling dependents when a model is deleted.

  Dependents for your model are typically declared via the `has_many/3` macro
  in your model's `schema` block. Oftentimes you will find a need to define behavior
  for a model's dependents when said model is deleted. This module defines the
  most common behaviors for dealing with dependents of a deleted model.

  ## Dependent options

  There are three different behaviors you can set for your dependents. These are:

  * `:delete_all` - Deletes all dependents without triggering lifecycle callbacks;
  * `:fetch_and_delete` - Deletes dependents and triggers any `before_delete` and `after_delete`
    callbacks on each dependent;
  * `:nilify_all` - Sets model reference to nil for each dependent without triggering any
    lifecycle callback;

  Keep in mind these options are only available for `has_many/3` macros.

  ## Alternatives

  Ecto also provides an `:on_delete` option when using `references/2` in migrations. This allows
  you to set what to perform when an entry is deleted in you schema and effectively, at the database
  level. When you want to push as much responsibilty down to the schema, that approach would better
  serve you.

  However, using the `:dependent` option in `has_many/3` would afford you more flexibility.
  It does not require you to run migrations every time you want to change the behavior for handling
  dependents.
  """

  alias Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  @doc """
  Deletes all records of dependent model and triggers `delete` lifecycle callbacks.
  """
  def fetch_and_delete(%Changeset{repo: repo} = changeset, assoc_queryable, assoc_key) do
    query  = assoc_query(changeset, assoc_queryable, assoc_key)
    assocs = repo.all(query)
    Enum.each assocs, fn (assoc) ->
      repo.delete!(assoc)
    end
    changeset
  end

  @doc """
  Deletes all records of dependent model while skipping their lifecycle callbacks.
  """
  def delete_all(%Changeset{repo: repo} = changeset, assoc_queryable, assoc_key) do
    query = assoc_query(changeset, assoc_queryable, assoc_key)
    repo.delete_all(query)
    changeset
  end

  @doc """
  Sets dependent's records reference to parent model to `nil`.

  This also does not trigger any lifecycle callbacks on the dependent model.
  """
  def nilify_all(%Changeset{repo: repo} = changeset, assoc_queryable, assoc_key) do
    query = assoc_query(changeset, assoc_queryable, assoc_key)
    repo.update_all(query, set: [{assoc_key, nil}])
    changeset
  end

  defp assoc_query(%Changeset{model: model}, assoc_queryable, assoc_key) do
    from(a in assoc_queryable, where: field(a, ^assoc_key) == ^model.id)
  end

  defmacro __before_compile__(env) do
    assocs = Module.get_attribute(env.module, :ecto_assocs) |> Enum.reverse

    for {_assoc_name, assoc} <- assocs, Map.from_struct(assoc)[:dependent] do
      dependent = assoc.dependent
      queryable = assoc.queryable
      assoc_key = assoc.assoc_key

      quote do
        before_delete Ecto.Model.Dependent, unquote(dependent), [unquote(queryable), unquote(assoc_key)]
      end
    end
  end
end
