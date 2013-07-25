Code.require_file "../test_helper.exs", __DIR__

  defmodule Ecto.RepoTest.MockAdapter do
    @behaviour Ecto.Adapter

    defmacro __using__(_opts), do: :ok
    def start_link(_repo), do: :ok
    def stop(_repo), do: :ok
    def all(_repo, _query), do: { :ok, [] }
    def create(_repo, _record), do: 42
    def update(_repo, _record), do: :ok
    def update_all(_repo, _query, _binds, _values), do: { :ok, 1 }
    def delete(_repo, _record), do: :ok
    def delete_all(_repo, _query), do: { :ok, 1 }
  end

  defmodule Ecto.RepoTest.MyRepo do
    use Ecto.Repo, adapter: Ecto.RepoTest.MockAdapter

    def url, do: ""
  end

  defmodule Ecto.RepoTest.MyEntity do
    use Ecto.Entity

    dataset "my_entity" do
      field :x, :string
    end
  end

  defmodule Ecto.RepoTest.MyEntityNoPK do
    use Ecto.Entity

    dataset "my_entity", nil do
      field :x, :string
    end
  end

defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Repo

  alias Ecto.RepoTest.MockAdapter
  alias Ecto.RepoTest.MyRepo
  alias Ecto.RepoTest.MyEntity
  alias Ecto.RepoTest.MyEntityNoPK
  require MyRepo

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
    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.get(MyEntityNoPK, 123)
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
    MyRepo.get(MyEntity, 123)
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

  test "get validation" do
    MyRepo.get(MyEntity, 123)
    MyRepo.get(MyEntity, "123")

    assert_raise ArgumentError, fn ->
      MyRepo.get(MyEntity, "abc")
    end

    assert_raise FunctionClauseError, fn ->
      MyRepo.get(MyEntity, :atom)
    end
  end

  test "repo validates update_all" do
    query = from(e in MyEntity, from: e2 in MyEntity)
    assert_raise(Ecto.InvalidQuery, fn ->
      MyRepo.update_all(query, [])
    end)

    query = from(e in MyEntity, select: e)
    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.update_all(query, [])
    end

    query = from(e in MyEntity, order_by: e.x)
    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.update_all(query, [])
    end

    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.update_all(p in MyEntity, y: "123")
    end

    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.update_all(p in MyEntity, x: 123)
    end

    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.update_all(e in MyEntity, [])
    end

    MyRepo.update_all(e in MyEntity, x: e.x)
    MyRepo.update_all(e in MyEntity, x: "123")
    MyRepo.update_all(MyEntity, x: "123")

    query = from(e in MyEntity, where: e.x == "123")
    MyRepo.update_all(query, x: "")
  end

  test "repo validates delete_all" do
    query = from(e in MyEntity, from: e2 in MyEntity)
    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.delete_all(query)
    end

    query = from(e in MyEntity, select: e)
    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.delete_all(query)
    end

    query = from(e in MyEntity, order_by: e.x)
    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.delete_all(query)
    end

    MyRepo.delete_all(MyEntity)

    query = from(e in MyEntity, where: e.x == "123")
    MyRepo.delete_all(query)
  end
end
