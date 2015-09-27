defmodule Ecto.Model do
  @moduledoc """
  Provides convenience functions for defining and working
  with models.

  `Ecto.Model` is built on top of `Ecto.Schema`. See
  `Ecto.Schema` for documentation on the `schema/2` macro,
  as well which fields, associations, types are available.

  ## Using

  When used, `Ecto.Model` imports itself. All the modules
  existing in `Ecto.Model.*` are brought in too:

    * `use Ecto.Model.Autogenerate` - automatically handle autogenerate columns before insertion
    * `use Ecto.Model.Dependent` - performs dependency (associations) management
    * `use Ecto.Model.Callbacks` - provides lifecycle callbacks
    * `use Ecto.Model.Timestamps` - automatically sets `inserted_at` and
      `updated_at` fields declared via `Ecto.Schema.timestamps/1`
    * `use Ecto.Model.OptimisticLock` - makes the `optimistic_lock/1` macro
      available

  However, you can avoid using `Ecto.Model` altogether in favor
  of cherry-picking any of the functionality above.

  ## Importing

  You may want to import this module in contexts where you are
  working with different models. For example, in a web application,
  you may want to import this module into your plugs to provide
  conveniences for building and accessing model information.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Model
      import Ecto.Changeset

      use Ecto.Model.OptimisticLock
      use Ecto.Model.Timestamps
      use Ecto.Model.Dependent
      use Ecto.Model.Autogenerate
      use Ecto.Model.Callbacks
    end
  end

  @type t :: %{__struct__: atom}

  @doc """
  Returns the model primary keys as a keyword list.
  """
  @spec primary_key(t) :: Keyword.t
  def primary_key(%{__struct__: model} = struct) do
    Enum.map model.__schema__(:primary_key), fn(field) ->
      {field, Map.fetch!(struct, field)}
    end
  end

  @doc """
  Returns the model primary keys as a keyword list.

  Raises `Ecto.NoPrimaryKeyFieldError` if the model has no
  primary key field.
  """
  @spec primary_key!(t) :: Keyword.t | no_return
  def primary_key!(struct) do
    case primary_key(struct) do
      [] -> raise Ecto.NoPrimaryKeyFieldError, model: struct
      pk -> pk
    end
  end

  @doc """
  Builds a struct from the given `assoc` in `model`.

  ## Examples

  If the relationship is a `has_one` or `has_many` and
  the key is set in the given model, the key will automatically
  be set in the built association:

      iex> post = Repo.get(Post, 13)
      %Post{id: 13}
      iex> build(post, :comments)
      %Comment{id: nil, post_id: 13}

  Note though it doesn't happen with belongs to cases, as the
  key is often the primary key and such is usually generated
  dynamically:

      iex> comment = Repo.get(Comment, 13)
      %Comment{id: 13, post_id: 25}
      iex> build(comment, :post)
      %Post{id: nil}

  You can also pass the attributes, which can be a map or
  a keyword list, to set the struct's fields except the
  association key.

      iex> build(post, :comments, text: "cool")
      %Comment{id: nil, post_id: 13, text: "cool"}

      iex> build(post, :comments, %{text: "cool"})
      %Comment{id: nil, post_id: 13, text: "cool"}

      iex> build(post, :comments, post_id: 1)
      %Comment{id: nil, post_id: 13}
  """
  def build(%{__struct__: model} = struct, assoc, attributes \\ %{}) do
    assoc = Ecto.Association.association_from_model!(model, assoc)
    assoc.__struct__.build(assoc, struct, attributes)
  end

  @doc """
  Builds a query for the association in the given model or models.

  ## Examples

  In the example below, we get all comments associated to the given
  post:

      post = Repo.get Post, 1
      Repo.all assoc(post, :comments)

  `assoc/2` can also receive a list of posts, as long as the posts are
  not empty:

      posts = Repo.all from p in Post, where: is_nil(p.published_at)
      Repo.all assoc(posts, :comments)

  """
  def assoc(model_or_models, assoc) do
    structs = List.wrap(model_or_models)

    if structs == [] do
      raise ArgumentError, "cannot retrieve association #{inspect assoc} for empty list"
    end

    model = hd(structs).__struct__
    assoc = %{owner_key: owner_key} =
      Ecto.Association.association_from_model!(model, assoc)

    values =
      Enum.uniq for(struct <- structs,
        assert_struct!(model, struct),
        key = Map.fetch!(struct, owner_key),
        do: key)

    assoc.__struct__.assoc_query(assoc, values)
  end

  @doc """
  Updates the model metadata.

  It is possible to set:

    * `:source` - changes the model query source
    * `:prefix` - changes the model query prefix
    * `:context` - changes the model meta context
    * `:state` - changes the model state
  """
  @spec put_meta(Ecto.Model.t, [source: String.t, prefix: String.t,
                                context: term, state: :built | :loaded | :deleted]) :: Ecto.Model.t
  def put_meta(model, opts) do
    update_in model.__meta__, &update_meta(opts, &1)
  end

  defp update_meta([{:state, state}|t], meta) do
    if state in [:built, :loaded, :deleted] do
      update_meta t, %{meta | state: state}
    else
      raise ArgumentError, "invalid state #{inspect state}"
    end
  end

  defp update_meta([{:source, source}|t], %{source: {prefix, _}} = meta) do
    update_meta t, %{meta | source: {prefix, source}}
  end

  defp update_meta([{:prefix, prefix}|t], %{source: {_, source}} = meta) do
    update_meta t, %{meta | source: {prefix, source}}
  end

  defp update_meta([{:context, context}|t], meta) do
    update_meta t, %{meta | context: context}
  end

  defp update_meta([], meta) do
    meta
  end

  defp update_meta([{k, _}], _meta) do
    raise ArgumentError, "unknown meta key #{inspect k}"
  end

  @doc false
  # TODO: Deprecate on Ecto 1.1
  def put_source(model, new_source, new_prefix \\ nil) do
    IO.puts :stderr, "warning: Ecto.Model.put_source/3 is deprecated in favor of " <>
                     "Ecto.Model.put_meta/2\n#{Exception.format_stacktrace}"
    put_in model.__meta__.source, {new_prefix, new_source}
  end

  defp assert_struct!(model, %{__struct__: struct}) do
    if struct != model do
      raise ArgumentError, "expected a homogeneous list containing the same struct, " <>
                           "got: #{inspect model} and #{inspect struct}"
    else
      true
    end
  end
end
