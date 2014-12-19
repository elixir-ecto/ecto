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
  alias Ecto.MockRepo
  alias Ecto.RepoTest.MyModel
  alias Ecto.RepoTest.MyModelList
  alias Ecto.RepoTest.MyModelNoPK
  require MockRepo

  test "handles environment support" do
    defmodule EnvRepo do
      # Use a variable to ensure it is properly expanded at runtime
      env = :dev
      use Ecto.Repo, adapter: Ecto.MockAdapter, env: env
      def conf(:dev), do: "dev_sample"
    end

    assert EnvRepo.conf == "dev_sample"
  end

  test "needs model with primary key" do
    model = %MyModelNoPK{x: "abc"}
    assert_raise Ecto.NoPrimaryKey, fn ->
      MockRepo.update(model)
    end
    assert_raise Ecto.NoPrimaryKey, fn ->
      MockRepo.delete(model)
    end
    assert_raise Ecto.NoPrimaryKey, fn ->
      MockRepo.get(MyModelNoPK, 123)
    end
  end

  test "needs model with primary key value" do
    model = %MyModel{x: "abc"}

    assert_raise Ecto.NoPrimaryKey, fn ->
      MockRepo.update(model)
    end
    assert_raise Ecto.NoPrimaryKey, fn ->
      MockRepo.delete(model)
    end
  end

  test "works with primary key value" do
    model = %MyModel{id: 1, x: "abc"}

    MockRepo.update(model)
    MockRepo.delete(model)
    MockRepo.get(MyModel, 123)
  end

  test "validate model types" do
    model = %MyModel{x: 123}

    assert_raise Ecto.InvalidModel, fn ->
      MockRepo.insert(model)
    end

    model = %MyModel{id: 1, x: 123}

    assert_raise Ecto.InvalidModel, fn ->
      MockRepo.update(model)
    end
    assert_raise Ecto.InvalidModel, fn ->
      MockRepo.delete(model)
    end
  end

  test "get validation" do
    MockRepo.get(MyModel, 123)

    assert_raise ArgumentError, fn ->
      MockRepo.get(MyModel, :atom)
    end
  end

  test "repo validates update_all" do
    query = from(e in MyModel, select: e)
    assert_raise Ecto.QueryError, fn ->
      MockRepo.update_all(query, [])
    end

    query = from(e in MyModel, order_by: e.x)
    assert_raise Ecto.QueryError, fn ->
      MockRepo.update_all(query, [])
    end

    assert_raise Ecto.QueryError, fn ->
      MockRepo.update_all(p in MyModel, y: "123")
    end

    assert_raise Ecto.QueryError, fn ->
      MockRepo.update_all(p in MyModel, x: 123)
    end

    assert_raise Ecto.QueryError, fn ->
      MockRepo.update_all(e in MyModel, [])
    end

    MockRepo.update_all(e in MyModel, x: nil)
    MockRepo.update_all(e in MyModel, x: e.x)
    MockRepo.update_all(e in MyModel, x: "123")
    MockRepo.update_all(MyModel, x: "123")

    query = from(e in MyModel, where: e.x == "123")
    MockRepo.update_all(query, x: "")
  end

  test "repo validates delete_all" do
    query = from(e in MyModel, select: e)
    assert_raise Ecto.QueryError, fn ->
      MockRepo.delete_all(query)
    end

    query = from(e in MyModel, order_by: e.x)
    assert_raise Ecto.QueryError, fn ->
      MockRepo.delete_all(query)
    end

    MockRepo.delete_all(MyModel)

    query = from(e in MyModel, where: e.x == "123")
    MockRepo.delete_all(query)
  end

  test "unsupported type" do
    assert_raise ArgumentError, fn ->
      MockRepo.insert(%MyModel{x: {123}})
    end
  end

  test "list value types incorrect" do
    assert_raise Ecto.InvalidModel, fn ->
      MockRepo.insert(%MyModelList{l1: [1, 2, 3]})
    end
  end

  test "parse_url is available" do
    assert MockRepo.url[:hostname] == "localhost"
  end
end
