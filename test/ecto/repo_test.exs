defmodule Ecto.RepoTest.MyModel do
  use Ecto.Model

  schema "my_model" do
    field :x, :string
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

    assert_raise Ecto.NoPrimaryKeyError, fn ->
      MockRepo.update(model)
    end

    assert_raise Ecto.NoPrimaryKeyError, fn ->
      MockRepo.delete(model)
    end

    assert_raise Ecto.NoPrimaryKeyError, fn ->
      MockRepo.get(MyModelNoPK, 123)
    end
  end

  test "needs model with primary key value" do
    model = %MyModel{x: "abc"}

    assert_raise Ecto.NoPrimaryKeyError, fn ->
      MockRepo.update(model)
    end

    assert_raise Ecto.NoPrimaryKeyError, fn ->
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

    assert_raise Ecto.InvalidModelError, fn ->
      MockRepo.insert(model)
    end

    model = %MyModel{id: 1, x: 123}

    assert_raise Ecto.InvalidModelError, fn ->
      MockRepo.update(model)
    end
  end

  test "repo validates get" do
    MockRepo.get(MyModel, 123)

    message = ~r"value `:atom` in `where` cannot be cast to type :integer in query"
    assert_raise Ecto.CastError, message, fn ->
      MockRepo.get(MyModel, :atom)
    end

    message = ~r"query in `get` must have a from expression with a model in query"
    assert_raise Ecto.QueryError, message, fn ->
      MockRepo.get(%Ecto.Query{}, :atom)
    end
  end

  test "repo validates update_all" do
    # Success
    MockRepo.update_all(e in MyModel, x: nil)
    MockRepo.update_all(e in MyModel, x: e.x)
    MockRepo.update_all(e in MyModel, x: "123")
    MockRepo.update_all(MyModel, x: "123")

    query = from(e in MyModel, where: e.x == "123")
    MockRepo.update_all(query, x: "")

    # Failures
    message = "no fields given to `update_all`"
    assert_raise ArgumentError, message, fn ->
      MockRepo.update_all(from(e in MyModel, select: e), [])
    end

    assert_raise ArgumentError, "value `123` in `update_all` cannot be cast to type :string", fn ->
      MockRepo.update_all(p in MyModel, x: ^123)
    end

    message = ~r"only `where` expressions are allowed in query"
    assert_raise Ecto.QueryError, message, fn ->
      MockRepo.update_all(from(e in MyModel, order_by: e.x), x: "123")
    end

    message = "field `Ecto.RepoTest.MyModel.y` in `update_all` does not exist in the model source"
    assert_raise Ecto.InvalidModelError, message, fn ->
      MockRepo.update_all(p in MyModel, y: "123")
    end
  end

  test "repo validates delete_all" do
    # Success
    MockRepo.delete_all(MyModel)

    query = from(e in MyModel, where: e.x == "123")
    MockRepo.delete_all(query)

    # Failures
    assert_raise Ecto.QueryError, fn ->
      MockRepo.delete_all from(e in MyModel, select: e)
    end

    assert_raise Ecto.QueryError, fn ->
      MockRepo.delete_all from(e in MyModel, order_by: e.x)
    end
  end

  test "repo validates preload" do
    message = ~r"source in from expression needs to be directly selected when using preload"
    assert_raise Ecto.QueryError, message, fn ->
      MockRepo.all MyModel |> preload(:hello) |> select([m], m.x)
    end
  end

  test "parse_url is available" do
    assert MockRepo.url[:hostname] == "localhost"
  end
end
