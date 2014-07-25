defmodule Ecto.RepoTest.MockAdapter do
  @behaviour Ecto.Adapter

  defmacro __using__(_opts), do: :ok
  def start_link(_repo, _opts), do: :ok
  def stop(_repo), do: :ok
  def all(_repo, _query, _opts), do: []
  def insert(_repo, record, _opts) do
    record.id(45)
  end
  def update(_repo, _record, _opts), do: 1
  def update_all(_repo, _query, _values, _opts), do: 1
  def delete(_repo, _record, _opts), do: 1
  def delete_all(_repo, _query, _opts), do: 1
end

defmodule Ecto.RepoTest.MyRepo do
  use Ecto.Repo, adapter: Ecto.RepoTest.MockAdapter

  def conf, do: []
  def priv, do: app_dir(:ecto, "priv/db")
  def url,  do: parse_url("ecto://user@localhost/db")
end

defmodule Ecto.RepoTest.MyModel do
  use Ecto.Model

  schema "my_model" do
    field :x, :string
  end
end

defmodule Ecto.RepoTest.MyModelList do
  use Ecto.Model

  schema "my_model" do
    field :l1, {:array, :string}
  end
end

defmodule Ecto.RepoTest.MyModelNoPK do
  use Ecto.Model

  schema "my_model", primary_key: false do
    field :x, :string
  end
end

defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.RepoTest.MyRepo
  alias Ecto.RepoTest.MyModel
  alias Ecto.RepoTest.MyModelList
  alias Ecto.RepoTest.MyModelNoPK
  require MyRepo

  test "repo validates query" do
    import Ecto.Query

    assert_raise Ecto.Query.TypeCheckError, fn ->
      MyRepo.all(from(m in MyModel, select: m.x + 1))
    end

    assert_raise Ecto.Query.TypeCheckError, fn ->
      MyRepo.one(from(m in MyModel, select: m.x + 1))
    end
  end

  test "handles environment support" do
    defmodule EnvRepo do
      # Use a variable to ensure it is properly expanded at runtime
      env = :dev
      use Ecto.Repo, adapter: Ecto.RepoTest.MockAdapter, env: env
      def conf(:dev), do: "dev_sample"
    end

    assert EnvRepo.conf == "dev_sample"
  end

  test "needs model with primary key" do
    model = %MyModelNoPK{x: "abc"}
    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.update(model)
    end
    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.delete(model)
    end
    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.get(MyModelNoPK, 123)
    end
  end

  test "needs model with primary key value" do
    model = %MyModel{x: "abc"}

    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.update(model)
    end
    assert_raise Ecto.NoPrimaryKey, fn ->
      MyRepo.delete(model)
    end
  end

  test "works with primary key value" do
    model = %MyModel{id: 1, x: "abc"}

    MyRepo.update(model)
    MyRepo.delete(model)
    MyRepo.get(MyModel, 123)
  end

  test "validate model types" do
    model = %MyModel{x: 123}

    assert_raise Ecto.InvalidModel, fn ->
      MyRepo.insert(model)
    end

    model = %MyModel{id: 1, x: 123}

    assert_raise Ecto.InvalidModel, fn ->
      MyRepo.update(model)
    end
    assert_raise Ecto.InvalidModel, fn ->
      MyRepo.delete(model)
    end
  end

  test "get validation" do
    MyRepo.get(MyModel, 123)

    assert_raise ArgumentError, fn ->
      MyRepo.get(MyModel, :atom)
    end
  end

  test "repo validates update_all" do
    query = from(e in MyModel, select: e)
    assert_raise Ecto.QueryError, fn ->
      MyRepo.update_all(query, [])
    end

    query = from(e in MyModel, order_by: e.x)
    assert_raise Ecto.QueryError, fn ->
      MyRepo.update_all(query, [])
    end

    assert_raise Ecto.QueryError, fn ->
      MyRepo.update_all(p in MyModel, y: "123")
    end

    assert_raise Ecto.QueryError, fn ->
      MyRepo.update_all(p in MyModel, x: 123)
    end

    assert_raise Ecto.QueryError, fn ->
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
    assert_raise Ecto.QueryError, fn ->
      MyRepo.delete_all(query)
    end

    query = from(e in MyModel, order_by: e.x)
    assert_raise Ecto.QueryError, fn ->
      MyRepo.delete_all(query)
    end

    MyRepo.delete_all(MyModel)

    query = from(e in MyModel, where: e.x == "123")
    MyRepo.delete_all(query)
  end

  test "unsupported type" do
    assert_raise ArgumentError, fn ->
      MyRepo.insert(%MyModel{x: {123}})
    end
  end

  test "list value types incorrect" do
    assert_raise Ecto.InvalidModel, fn ->
      MyRepo.insert(%MyModelList{l1: %Ecto.Tagged{value: [1, 2, 3], type: {:array, :integer}}})
    end
  end

  test "app_dir is available" do
    assert MyRepo.priv == Path.expand("../../_build/shared/lib/ecto/priv/db", __DIR__)
  end

  test "parse_url is available" do
    assert MyRepo.url[:hostname] == "localhost"
  end
end
