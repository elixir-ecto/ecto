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

  import Ecto.Query, only: [from: 2]
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
  def assoc(model_or_models, assoc)

  # TODO: Make this polymorphic
  # TODO: Test me
  def assoc(model, assoc) when is_map(model) and is_atom(assoc) do
    %{owner_key: key, assoc: assoc, assoc_key: assoc_key} = reflection(model, assoc)

    from x in assoc,
      where: field(x, ^assoc_key) == ^Map.fetch!(model, key)
  end

  def assoc([], assoc) when is_atom(assoc) do
    raise ArgumentError, "cannot retrieve association #{inspect assoc} for empty list"
  end

  def assoc([h|_] = structs, assoc) when is_atom(assoc) do
    %{owner_key: key, owner: owner, assoc_key: assoc_key, assoc: assoc} = reflection(h, assoc)

    values =
      for struct <- structs,
          key =  Map.fetch!(struct, key) do
        %{__struct__: model} = struct

        if model != owner do
          raise ArgumentError, "list given to `assoc/2` must have the same struct, " <>
                               "got: #{inspect model} and #{inspect owner}"
        end

        key
      end

    from x in assoc, where: field(x, ^assoc_key) in ^values
  end

  defp reflection(%{__struct__: model}, assoc) do
    model.__schema__(:association, assoc) ||
      raise ArgumentError, "model #{inspect model} does not have association #{inspect assoc}"
  end
end
