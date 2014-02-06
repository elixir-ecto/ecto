defmodule Mix.Tasks.Ecto.Gen.Model do
  use Mix.Task
  import Mix.Tasks.Ecto
  import Mix.Generator

  @shortdoc "Generates an ecto model, entity and migration"

  @moduledoc """
  Generates a model, entity and migration for a given repo.

  It will create the following files:
    lib/<model_name>.ex
    migrations/create_<model_name>_table.exs
    test/<model_name>_test.ex

  Optional field names and types can be added to automatically generate the
  column specifications in the migration and field entries in the model

  ## Examples

    mix.ecto.gen.model.entity MyApp.Repo MyModel field1:string field2:string...
  """

  def run(args) do
    Mix.Tasks.Ecto.Gen.Model.Entity.run(args)
    Mix.Tasks.Ecto.Gen.Model.Migration.run(args)
  end
end
