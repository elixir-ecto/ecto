defmodule Ecto.Migration.Config do
  @moduledoc false

  @doc """
  Retrieves the `:ecto_migration` configuration for `:primary_key`
  """
  def primary_key do
    default = {:version, :integer, []}

    app()
    |> Application.get_env(:ecto_migration, primary_key: default)
    |> Keyword.get(:primary_key)
  end

  @doc """
  Retrieves the column name from primary_key/1
  """
  def primary_key_column(:name) do
    elem(primary_key, 0)
  end

  @doc """
  Retrieves the column type from primary_key/1
  """
  def primary_key_column(:type) do
    type = elem(primary_key, 1)
    if type == :integer do :bigint else type end
  end

  defp app do
    Mix.Project.config |> Keyword.fetch!(:app)
  end
end
