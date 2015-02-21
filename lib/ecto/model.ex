defmodule Ecto.Model do
  @moduledoc """
  Provides convenience functions for defining and working
  with models.

  ## Using

  When used, `Ecto.Model` works as an "umbrella" module that adds
  common functionality to your module:

    * `use Ecto.Schema` - provides the API necessary to define schemas
    * `import Ecto.Changeset` - functions for building and manipulating changesets
    * `import Ecto.Model` - functions for working with models and their associations
    * `import Ecto.Query` - functions for generating and manipulating queries

  Plus all the modules existing in `Ecto.Model.*` are brought in
  too:

    * `use Ecto.Model.Callbacks` - provides lifecycle callbacks
    * `use Ecto.Model.Timestamps` - automatically set `inserted_at` and
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
      import Ecto.Changeset
      import Ecto.Query

      import Ecto.Model
      use Ecto.Model.OptimisticLock
      use Ecto.Model.Timestamps
      use Ecto.Model.Callbacks
    end
  end

  @type t :: %{__struct__: atom}

  @doc """
  Returns the model primary key value.

  Raises `Ecto.NoPrimaryKeyError` if model has no primary key field.
  """
  @spec primary_key(t) :: any
  def primary_key(struct) do
    Map.fetch!(struct, primary_key_field(struct))
  end

  defp primary_key_field(%{__struct__: model}) do
    model.__schema__(:primary_key) || raise Ecto.NoPrimaryKeyError, model: model
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

      iex> comment = Repo.get(Post, 13)
      %Comment{id: 13, post_id: 25}
      iex> build(comment, :post)
      %Post{id: nil}
  """
  def build(%{__struct__: model} = struct, assoc) do
    assoc = Ecto.Associations.association_from_model!(model, assoc)
    assoc.__struct__.build(assoc, struct)
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
      Ecto.Associations.association_from_model!(model, assoc)

    values =
      for struct <- structs,
        assert_struct!(model, struct),
        key = Map.fetch!(struct, owner_key),
        do: key

    assoc.__struct__.assoc_query(assoc, values)
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
