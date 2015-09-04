defmodule Ecto.Model.Dependent do
  @moduledoc """
  Defines callbacks for handling dependencies (associations).

  Such callbacks are typically declared via the `has_many/3` macro
  in your model's `schema` block. For example:

      has_many :comments, MyApp.Comment, on_delete: :fetch_and_delete

  ## `:on_delete` options

  There are four different behaviors you can set for your associations
  when the parent is deleted:

    * `:nothing` - Does nothing to the association;

    * `:delete_all` - Deletes all associations without triggering lifecycle callbacks;

    * `:nilify_all` - Sets model reference to nil for each association without triggering
      any lifecycle callback;

    * `:fetch_and_delete` - Explicitly fetch all associations and delete them one by one,
      triggering any `before_delete` and `after_delete` callbacks;

  Keep in mind these options are only available for `has_many/3` macros.

  ## Alternatives

  Ecto also provides an `:on_delete` option when using `references/2` in migrations.
  This allows you to set what to perform when an entry is deleted in your schema
  effectively at the database level. Relying on the database is often the safest
  way to perform this operation and should be preferred.

  However using the `:on_delete` option may be more flexible specially if you have
  logic that needs to be expressed on the application side or if your database does
  not support references.
  """

  @on_delete_callbacks [:fetch_and_delete, :nilify_all, :delete_all]
  alias Ecto.Changeset

  defmacro __using__(_) do
    quote do
      @before_compile Ecto.Model.Dependent
    end
  end

  @doc false
  def fetch_and_delete(%Changeset{repo: repo, model: model} = changeset, assoc_field, _related_key) do
    query  = Ecto.Model.assoc(model, assoc_field)
    assocs = repo.all(query)
    Enum.each assocs, fn (assoc) -> repo.delete!(assoc) end
    changeset
  end

  @doc false
  def delete_all(%Changeset{repo: repo, model: model} = changeset, assoc_field, _related_key) do
    query = Ecto.Model.assoc(model, assoc_field)
    repo.delete_all(query)
    changeset
  end

  @doc false
  def nilify_all(%Changeset{repo: repo, model: model} = changeset, assoc_field, related_key) do
    query = Ecto.Model.assoc(model, assoc_field)
    repo.update_all(query, set: [{related_key, nil}])
    changeset
  end

  defmacro __before_compile__(env) do
    assocs = Module.get_attribute(env.module, :ecto_assocs)

    for {_assoc_name, assoc} <- assocs,
        Map.get(assoc, :on_delete) in @on_delete_callbacks do
      on_delete   = assoc.on_delete
      related_key   = assoc.related_key
      assoc_field = assoc.field

      quote do
        before_delete Ecto.Model.Dependent, unquote(on_delete),
                      [unquote(assoc_field), unquote(related_key)]
      end
    end
  end
end
