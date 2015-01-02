defmodule Ecto.Model do
  @moduledoc """
  Models are Elixir modules with Ecto-specific behaviour.

  This module provides some convenience functions for working
  with models.

  ## Using

  When used, this module works as an "umbrella" module that adds
  a bunch of functionality to your module:

    * `Ecto.Model.Schema` - provides the API necessary to define schemas;
    * `Ecto.Model.Callbacks` - provides lifecycle callbacks;
    * `Ecto.Model.Validations` - helpers for validations;

  By using `Ecto.Model` all the functionality above is included
  and both `Ecto.Model` and `Ecto.Query` modules are imported.
  However, you can avoid using `Ecto.Model` altogether in favor
  of cherry picking the functionality above.

  ## Importing

  You may want to import this module in contexts where you are
  working with different models. For example, in a web application,
  you may want to import this module into your plugs to provide
  conveniences for assigning, building and accessing model information.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Ecto.Model.Callbacks
      use Ecto.Model.Schema
      use Ecto.Model.Validations

      import Ecto.Model
      import Ecto.Query
    end
  end

  @type t :: map

  @doc """
  Returns the model primary key value.

  Raises `Ecto.NoPrimaryKeyError` if model has no primary key.
  """
  @spec primary_key(t) :: any
  def primary_key(struct) do
    Map.fetch!(struct, primary_key_field(struct))
  end

  defp primary_key_field(%{__struct__: model}) do
    model.__schema__(:primary_key) || raise Ecto.NoPrimaryKeyError, model: model
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

    {refl, values} = Ecto.Associations.owner_keys structs, assoc
    refl.__struct__.assoc_query(refl, values)
  end
end
