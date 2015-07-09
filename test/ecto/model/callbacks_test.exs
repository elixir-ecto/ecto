Code.require_file "../../support/test_repo.exs", __DIR__
alias Ecto.TestRepo

defmodule Ecto.Model.CallbacksTest do
  use ExUnit.Case, async: true

  defmodule SomeCallback do
    use Ecto.Model

    schema "some_callback" do
      field :x, :string, default: ""
    end

    before_delete __MODULE__, :add_to_x
    before_delete __MODULE__, :add_to_x, [%{str: "2"}]
    before_delete :add_to_x
    before_delete :add_to_x, [%{str: "2"}]

    before_update :bad_callback

    def add_to_x(changeset, %{str: str} \\ %{str: "1"}) do
      update_in changeset.model.x, &(&1 <> "," <> str)
    end

    defp bad_callback(_changeset) do
      nil
    end
  end

  test "defines functions for callbacks" do
    assert function_exported?(SomeCallback, :before_delete, 1)
  end

  test "doesn't define callbacks for not-registered events" do
    refute function_exported?(SomeCallback, :after_delete, 1)
  end

  test "applies callbacks" do
    changeset = %Ecto.Changeset{model: %SomeCallback{x: "x"}}

    assert Ecto.Model.Callbacks.__apply__(SomeCallback, :before_delete, changeset) ==
           %Ecto.Changeset{model: %SomeCallback{x: "x,1,2,1,2"}}
  end

  test "raises on bad callbacks" do
    msg = "expected `before_update` callbacks to return a Ecto.Changeset, got: nil"
    assert_raise ArgumentError, msg, fn ->
      Ecto.Model.Callbacks.__apply__(SomeCallback, :before_update, %Ecto.Changeset{})
    end
  end

  ## Repo integration

  defmodule AllCallback do
    use Ecto.Model

    schema "all_callback" do
      field :x, :string, default: ""
      field :y, :string, default: ""
      field :z, :string, default: ""
      field :before, :any, virtual: true
      field :after,  :any, virtual: true
      field :xyz, :string, virtual: true
    end

    before_insert __MODULE__, :changeset_before
    after_insert  __MODULE__, :changeset_after
    before_update __MODULE__, :changeset_before
    after_update  __MODULE__, :changeset_after
    before_delete __MODULE__, :changeset_before
    after_delete  __MODULE__, :changeset_after
    after_load    __MODULE__, :changeset_load

    def changeset_before(%{repo: TestRepo} = changeset) do
      put_in(changeset.model.before, changeset.changes)
      |> delete_change(:z)
    end

    def changeset_after(%{repo: TestRepo} = changeset) do
      put_in(changeset.model.after, changeset.changes)
    end

    def changeset_load(model) do
      Map.put(model, :xyz, model.x <> model.y <> model.z)
    end
  end

  test "wraps operations into transactions if callback present" do
    model = %SomeCallback{x: "x"}
    TestRepo.insert! model
    refute_received {:transaction, _fun}

    model = %AllCallback{x: "x"}
    TestRepo.insert! model
    assert_received {:transaction, _fun}
  end

  test "before_insert and after_insert with model" do
    model = %AllCallback{x: "x"}
    model = TestRepo.insert! model
    assert model.before == %{x: "x", y: "", z: ""}
    assert model.after == %{x: "x", y: ""}

    model = %AllCallback{id: 1, x: "x"}
    model = TestRepo.insert! model
    assert model.before == %{id: 1, x: "x", y: "", z: ""}
    assert model.after == %{id: 1, x: "x", y: ""}
  end

  test "before_update and after_update with model" do
    model = %AllCallback{id: 1, x: "x"}
    model = TestRepo.update! model
    assert model.before == %{x: "x", y: "", z: ""}
    assert model.after == %{x: "x", y: ""}
  end

  test "before_delete and after_delete with model" do
    model = %AllCallback{id: 1, x: "x"}
    model = TestRepo.delete! model
    assert model.before == %{}
    assert model.after == %{}
  end

  test "before_insert and after_insert with changeset" do
    changeset = Ecto.Changeset.cast(%AllCallback{x: "x", y: "z"},
                                    %{"y" => "y", "z" => "z"}, ~w(y z), ~w())
    model = TestRepo.insert! changeset
    assert model.before == %{x: "x", y: "y", z: "z"}
    assert model.after == %{x: "x", y: "y"}
    assert model.x == "x"
    assert model.y == "y"
    assert model.z == ""
  end

  test "before_update and after_update with changeset" do
    changeset = Ecto.Changeset.cast(%AllCallback{id: 1, x: "x", y: "z"},
                                    %{"y" => "y", "z" => "z"}, ~w(y z), ~w())
    model = TestRepo.update! changeset
    assert model.before == %{y: "y", z: "z"}
    assert model.after == %{y: "y"}
    assert model.x == "x"
    assert model.y == "y"
    assert model.z == ""
  end

  test "before_update and after_update with empty changeset" do
    changeset = Ecto.Changeset.change(%AllCallback{id: 1, x: "x", y: "z"}, %{})
    model = TestRepo.update! changeset
    assert model.before == nil
    assert model.after == nil
    assert model.x == "x"
    assert model.y == "z"
    assert model.z == ""

    changeset = Ecto.Changeset.change(%AllCallback{id: 1, x: "x", y: "z"}, %{})
    model = TestRepo.update! changeset, force: true
    assert model.before == %{}
    assert model.after == %{}
    assert model.x == "x"
    assert model.y == "z"
    assert model.z == ""
  end

  test "before_insert and after_insert with id in changeset" do
    changeset = Ecto.Changeset.cast(%AllCallback{},
                                    %{"id" => 1}, ~w(id), ~w())
    model = TestRepo.insert! changeset
    assert model.before == %{id: 1, x: "", y: "", z: ""}
    assert model.after == %{id: 1, x: "", y: ""}
  end

  test "before_update and after_update with id in changeset" do
    changeset = Ecto.Changeset.cast(%AllCallback{id: 0},
                                    %{"id" => 1}, ~w(id), ~w())
    model = TestRepo.update! changeset
    assert model.before == %{id: 1}
    assert model.after == %{id: 1}
  end

  test "after_load with model" do
    model = Ecto.Schema.Serializer.load!(AllCallback, "hello", {2, {nil, nil, 1, "x", "y", "z"}}, %{})
    assert model.id == 1
    assert model.xyz == "xyz"
    assert model.__meta__ == %Ecto.Schema.Metadata{source: "hello", state: :loaded}
  end
end
