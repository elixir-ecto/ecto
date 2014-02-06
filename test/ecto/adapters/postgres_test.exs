defmodule Ecto.Adapters.PostgresTest do
  use ExUnit.Case, async: true

  defmodule Repo do
    use Ecto.Repo, adapter: Ecto.Adapters.Postgres
    
    def url do
      "ecto://postgres:postgres@localhost/repo"
    end
  end

  test "stores pool_name metadata" do
    assert Repo.__postgres__(:pool_name) == __MODULE__.Repo.Pool
  end

  test "gets type mappings for field atom" do
    assert Repo.adapter.type_map.for(:string) == :text
    assert Repo.adapter.type_map.for(:integer) == :integer
  end
end
