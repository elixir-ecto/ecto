defmodule Ecto.Adapters.MysqlTest do
  use ExUnit.Case, async: true

  defmodule Repo do
    use Ecto.Repo, adapter: Ecto.Adapters.Mysql

    def url do
      "ecto://root:@localhost:3306/repo"
    end
  end

  test "stores conn_name metadata" do
    assert Repo.__mysql__(:conn_name) == __MODULE__.Repo.Conn
  end
end
