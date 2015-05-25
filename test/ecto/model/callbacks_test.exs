Code.require_file "../../support/mock_repo.exs", __DIR__
alias Ecto.MockRepo

defmodule Ecto.Model.CallbacksTest do
  use ExUnit.Case, async: true

  defmodule SomeCallback do
    use Ecto.Model

    schema "some_callback" do
      field :x, :integer, default: 0
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
      field :x, :integer, default: 0, read_after_writes: true
      field :y, :integer, default: 0
      field :z, :integer, default: 0
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

    def changeset_before(%{repo: MockRepo} = changeset) do
      put_in(changeset.model.before, changeset.changes)
      |> delete_change(:z)
    end

    def changeset_after(%{repo: MockRepo} = changeset) do
      put_in(changeset.model.after, changeset.changes)
    end

    def changeset_load(model) do
      Map.put(model, :xyz, model.x + model.y + model.z)
    end
  end

  test "wraps operations into transactions if callback present" do
    model = %SomeCallback{x: 1}
    MockRepo.insert model
    refute_received {:transaction, _fun}

    model = %AllCallback{x: 1}
    MockRepo.insert model
    assert_received {:transaction, _fun}
  end

  test "before_insert and after_insert with model" do
    model = %AllCallback{x: 1}
    model = MockRepo.insert model
    assert model.before == %{x: 1, y: 0, z: 0}
    assert model.after == %{x: 1, y: 0}
  end

  test "before_update and after_update with model" do
    model = %AllCallback{id: 1, x: 1}
    model = MockRepo.update model
    assert model.before == %{x: 1, y: 0, z: 0}
    assert model.after == %{x: 1, y: 0}
  end

  test "before_delete and after_delete with model" do
    model = %AllCallback{id: 1, y: 2}
    model = MockRepo.delete model
    assert model.before == %{}
    assert model.after == %{}
  end

  test "before_insert and after_insert with changeset" do
    changeset = Ecto.Changeset.cast(%AllCallback{x: 1, y: 3},
                                    %{"y" => 2, "z" => 3}, ~w(y z), ~w())
    model = MockRepo.insert changeset
    assert model.before == %{x: 1, y: 2, z: 3}
    assert model.after == %{x: 1, y: 2}
    assert model.x == 2 # From read after writes
    assert model.y == 2
    assert model.z == 0 # Ignored with delete_change
  end

  test "before_update and after_update with changeset" do
    changeset = Ecto.Changeset.cast(%AllCallback{id: 1, x: 1, y: 3},
                                    %{"y" => 2, "z" => 3}, ~w(y z), ~w())
    model = MockRepo.update changeset
    assert model.before == %{y: 2, z: 3}
    assert model.after == %{y: 2}
    assert model.x == 2 # From read after writes
    assert model.y == 2
    assert model.z == 0 # Ignored with delete_change
  end

  test "before_insert and after_insert with model and read after writes" do
    model = %AllCallback{id: 1, x: nil, y: 2}
    model = MockRepo.insert model
    assert model.before == %{id: 1, y: 2, z: 0}
    assert model.after == %{id: 1, y: 2}
  end

  test "before_insert and after_insert with changeset and read after writes" do
    # Nil from the model is discarded
    changeset = Ecto.Changeset.cast(%AllCallback{x: nil, y: 3},
                                    %{"y" => 2, "z" => 3}, ~w(y z), ~w())
    model = MockRepo.insert changeset
    assert model.before == %{y: 2, z: 3}
    assert model.after == %{y: 2}
    assert model.x == 2 # From read after writes
    assert model.y == 2

    # Nil from changeset is kept
    changeset = Ecto.Changeset.change(%AllCallback{}, x: nil, y: 2, z: 3)
    model = MockRepo.insert changeset
    assert model.before == %{x: nil, y: 2, z: 3}
    assert model.after == %{x: nil, y: 2}
    assert model.x == 2 # From read after writes
    assert model.y == 2
  end

  test "before_insert and after_insert with id in changeset" do
    changeset = Ecto.Changeset.cast(%AllCallback{},
                                    %{"id" => 1}, ~w(id), ~w())
    model = MockRepo.insert changeset
    assert model.before[:id] == 1
    assert model.after[:id] == 1
  end

  test "before_update and after_update with id in changeset" do
    changeset = Ecto.Changeset.cast(%AllCallback{id: 0},
                                    %{"id" => 1}, ~w(id), ~w())
    model = MockRepo.update changeset
    assert model.before[:id] == 1
    assert model.after[:id] == 1
  end

  test "after_load with model" do
    model = AllCallback.__schema__(:load, "hello", 2, {nil, nil, 1, 1, 2, 3})
    assert model.id == 1
    assert model.xyz == 6
    assert model.__meta__ == %Ecto.Schema.Metadata{source: "hello", state: :loaded}
  end
end
