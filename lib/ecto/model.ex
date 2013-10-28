defmodule Ecto.Model do
  @moduledoc """
  Models are Elixir modules with Ecto-specific behaviour.

  Entities in Ecto are simply data, all the behaviour exists in models.
  This module is an "umbrella" module that adds a bunch of functionality
  to your module:

  * `Ecto.Model.Queryable` - provides the API necessary to generate queries;
  * `Ecto.Model.Callbacks` - to be implemented;
  * `Ecto.Model.Validations` - helpers for validations;

  By using `Ecto.Model` all the functionality above is included,
  but you can cherry pick the ones you want to use.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Ecto.Model.Queryable
      use Ecto.Model.Validations
    end
  end
end

