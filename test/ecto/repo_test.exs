defmodule Ecto.RepoTest.MockAdapter do
  @behaviour Ecto.Adapter

  defmacro __using__(_opts), do: :ok
  def start_link(_repo), do: :ok
  def stop(_repo), do: :ok
  def all(_repo, _query), do: { :ok, [] }
  def create(_repo, _record), do: 42
  def update(_repo, _record), do: { :ok, 1 }
  def update_all(_repo, _query, _values), do: { :ok, 1 }
  def delete(_repo, _record), do: { :ok, 1 }
  def delete_all(_repo, _query), do: { :ok, 1 }
end

defmodule Ecto.RepoTest.MyRepo do
  use Ecto.Repo, adapter: Ecto.RepoTest.MockAdapter

  def url, do: ""
end

defmodule Ecto.RepoTest.MyModel do
  use Ecto.Model

  queryable "my_entity" do
    field :x, :string
  end
end

defmodule Ecto.RepoTest.MyModelNoPK do
  use Ecto.Model

  queryable "my_entity", nil do
    field :x, :string
  end
end

defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Repo

  alias Ecto.RepoTest.MockAdapter
  alias Ecto.RepoTest.MyRepo
  alias Ecto.RepoTest.MyModel
  alias Ecto.RepoTest.MyModelNoPK
  require MyRepo

  test "parse url" do
    url = Repo.parse_url("ecto://eric:hunter2@host:12345/mydb?size=10&a=b", 0)
    assert { :password, "hunter2" } in url
    assert { :username, "eric" } in url
    assert { :hostname, "host" } in url
    assert { :database, "mydb" } in url
    assert { :port, 12345 } in url
    assert { :size, "10" } in url
    assert { :a, "b" } in url
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

    assert_raise Ecto.TypeCheckError, fn ->
      MyRepo.all(from(m in MyModel, select: m.x + 1))
    end
  end

  test "needs entity with primary key" do
    entity = MyModelNoPK.new(x: "abc")
    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.update(entity)
    end
    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.delete(entity)
    end
    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.get(MyModelNoPK, 123)
    end
  end

  test "needs entity with primary key value" do
    entity = MyModel.new(x: "abc")

    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.update(entity)
    end
    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.delete(entity)
    end
  end

  test "works with primary key value" do
    entity = MyModel.new(id: 1, x: "abc")

    MyRepo.update(entity)
    MyRepo.delete(entity)
    MyRepo.get(MyModel, 123)
  end

  test "validate entity types" do
    entity = MyModel.new(x: 123)

    assert_raise Ecto.ValidationError, fn ->
      MyRepo.create(entity)
    end

    entity = MyModel.new(id: 1, x: 123)

    assert_raise Ecto.ValidationError, fn ->
      MyRepo.update(entity)
    end
    assert_raise Ecto.ValidationError, fn ->
      MyRepo.delete(entity)
    end
  end

  test "get validation" do
    MyRepo.get(MyModel, 123)
    MyRepo.get(MyModel, "123")

    assert_raise ArgumentError, fn ->
      MyRepo.get(MyModel, "abc")
    end

    assert_raise FunctionClauseError, fn ->
      MyRepo.get(MyModel, :atom)
    end
  end

  test "repo validates update_all" do
    query = from(e in MyModel, select: e)
    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.update_all(query, [])
    end

    query = from(e in MyModel, order_by: e.x)
    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.update_all(query, [])
    end

    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.update_all(p in MyModel, y: "123")
    end

    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.update_all(p in MyModel, x: 123)
    end

    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.update_all(e in MyModel, [])
    end

    MyRepo.update_all(e in MyModel, x: e.x)
    MyRepo.update_all(e in MyModel, x: "123")
    MyRepo.update_all(MyModel, x: "123")

    query = from(e in MyModel, where: e.x == "123")
    MyRepo.update_all(query, x: "")
  end

  test "repo validates delete_all" do
    query = from(e in MyModel, select: e)
    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.delete_all(query)
    end

    query = from(e in MyModel, order_by: e.x)
    assert_raise Ecto.InvalidQuery, fn ->
      MyRepo.delete_all(query)
    end

    MyRepo.delete_all(MyModel)

    query = from(e in MyModel, where: e.x == "123")
    MyRepo.delete_all(query)
  end

  test "unsupported type" do
    assert_raise Ecto.ValidationError, fn ->
      MyRepo.create(MyModel.Entity[x: {123}])
    end
  end
end
