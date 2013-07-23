Code.require_file "../test_helper.exs", __DIR__

defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  alias Ecto.Repo

  test "parse url" do
    assert Repo.parse_url("ecto://eric:hunter2@host:12345/mydb?size=10&a=b", 0) == [
           password: "hunter2",
           username: "eric",
           hostname: "host",
           database: "mydb",
           port: 12345,
           size: "10",
           a: "b" ]
  end

  test "parse invalid url" do
    assert_raise Ecto.InvalidURL, %r"not an ecto url", fn ->
      Repo.parse_url("http://eric:hunter2@host:123/mydb", 0)
    end

    assert_raise Ecto.InvalidURL, %r"url has to contain a username", fn ->
      Repo.parse_url("ecto://host:123/mydb", 0)
    end

    assert_raise Ecto.InvalidURL, %r"path should be a database name", fn ->
      Repo.parse_url("ecto://eric:hunter2@host:123/a/b/c", 0)
    end

    assert_raise Ecto.InvalidURL, %r"path should be a database name", fn ->
      Repo.parse_url("ecto://eric:hunter2@host:123/", 0)
    end
  end

  test "default port" do
    settings = Repo.parse_url("ecto://eric:hunter2@host/mydb", 54321)
    assert settings[:port] == 54321
  end

  test "optional password" do
    url = Repo.parse_url("ecto://eric@host:123/mydb", 0)
    refute url[:password]
  end

  defmodule MockAdapter do
    @behaviour Ecto.Adapter

    defmacro __using__(_opts), do: :ok
    def start_link(_repo), do: :ok
    def stop(_repo), do: :ok
    def all(_repo, _query), do: { :ok, [] }
    def create(_repo, _record), do: 42
    def update(_repo, _record), do: :ok
    def delete(_repo, _record), do: :ok
  end

  defmodule MyRepo do
    use Repo, adapter: MockAdapter

    def url, do: ""
  end

  defmodule MyEntity do
    use Ecto.Entity

    dataset "my_entity" do
      field :x, :string
    end
  end

  defmodule MyEntityNoPK do
    use Ecto.Entity

    dataset "my_entity", nil do
      field :x, :string
    end
  end

  test "repo validates query" do
    import Ecto.Query

    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.all(from(m in MyEntity, select: m.x + 1))
    end
  end

  test "needs entity with primary key" do
    entity = MyEntityNoPK[x: "abc"]

    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.update(entity)
    end
    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.delete(entity)
    end
  end

  test "needs entity with primary key value" do
    entity = MyEntity[x: "abc"]

    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.update(entity)
    end
    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.delete(entity)
    end
  end

  test "works with primary key value" do
    entity = MyEntity[id: 1, x: "abc"]

    MyRepo.update(entity)
    MyRepo.delete(entity)
  end

  test "validate entity types" do
    entity = MyEntity[x: 123]

    assert_raise Ecto.ValidationError, fn ->
      MyRepo.create(entity)
    end

    entity = MyEntity[id: 1, x: 123]

    assert_raise Ecto.ValidationError, fn ->
      MyRepo.update(entity)
    end
    assert_raise Ecto.ValidationError, fn ->
      MyRepo.delete(entity)
    end
  end
end
