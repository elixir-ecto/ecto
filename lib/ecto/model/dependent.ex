defmodule Ecto.Model.Dependent do

  alias Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  def fetch_and_delete(%Changeset{repo: repo} = changeset, assoc_queryable, assoc_key) do
    query  = assoc_query(changeset, assoc_queryable, assoc_key)
    assocs = repo.all(query)
    Enum.each assocs, fn (assoc) ->
      repo.delete!(assoc)
    end
    changeset
  end

  def delete_all(%Changeset{repo: repo} = changeset, assoc_queryable, assoc_key) do
    query = assoc_query(changeset, assoc_queryable, assoc_key)
    repo.delete_all(query)
    changeset
  end

  defmacro nilify_all(%Changeset{repo: repo} = changeset, assoc_queryable, assoc_key) do
    query = assoc_query(changeset, assoc_queryable, assoc_key)

    quote do
      repo.update_all(unquote(query), [{unquote(assoc_key), nil}])
      unquote(changeset)
    end
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
        after_delete Ecto.Model.Dependent, unquote(dependent), [unquote(queryable), unquote(assoc_key)]
      end
    end
  end
end
