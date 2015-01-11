Code.require_file "../../support/mock_repo.exs", __DIR__
alias Ecto.MockRepo

defmodule Ecto.Model.CallbacksTest do
  use ExUnit.Case, async: true

  defmodule DeleteCallback do
    use Ecto.Model

    schema "delete_callback" do
      field :x, :string, default: ""
    end

    before_delete __MODULE__, :add_before
    before_delete __MODULE__, :add_before

    before_update __MODULE__, :bad_callback

    def add_before(model),    do: %{model | x: model.x <> ",before"}
    def bad_callback(_model), do: nil
  end

  test "defines functions for callbacks" do
    assert function_exported?(DeleteCallback, :before_delete, 1)
  end

  test "doesn't define callbacks for not-registered events" do
    refute function_exported?(DeleteCallback, :after_delete, 1)
  end

  test "applies callbacks" do
    assert Ecto.Model.Callbacks.__apply__(DeleteCallback, :before_delete, %DeleteCallback{x: "x"}) ==
           %DeleteCallback{x: "x,before,before"}
  end

  test "raises on bad callbacks" do
    assert_raise ArgumentError, ~r/expected `before_update` callbacks to return a/, fn ->
      Ecto.Model.Callbacks.__apply__(DeleteCallback, :before_update, %DeleteCallback{x: "x"})
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
    end

    before_insert __MODULE__, :changeset_before
    after_insert  __MODULE__, :changeset_after
    before_update __MODULE__, :changeset_before
    after_update  __MODULE__, :changeset_after
    before_delete __MODULE__, :changeset_before
    after_delete  __MODULE__, :changeset_after

    def changeset_before(changeset) do
      put_in(changeset.model.before, changeset.changes)
      |> delete_change(:z)
    end

    def changeset_after(changeset) do
      put_in(changeset.model.after, changeset.changes)
    end
  end

  test "wraps operations into transactions if callback present" do
    model = %DeleteCallback{x: "x"}
    MockRepo.insert model
    refute_received {:transaction, _fun}

    model = %AllCallback{x: "x"}
    MockRepo.insert model
    assert_received {:transaction, _fun}
  end

  test "before_insert and after_insert with model" do
    model = %AllCallback{x: "x"}
    model = MockRepo.insert model
    assert model.before == %{x: "x", y: "", z: ""}
    assert model.after == %{x: "x", y: ""}

    model = %AllCallback{id: 1, x: "x"}
    model = MockRepo.insert model
    assert model.before == %{id: 1, x: "x", y: "", z: ""}
    assert model.after == %{id: 1, x: "x", y: ""}
  end

  test "before_update and after_update with model" do
    model = %AllCallback{id: 1, x: "x"}
    model = MockRepo.update model
    assert model.before == %{id: 1, x: "x", y: "", z: ""}
    assert model.after == %{id: 1, x: "x", y: ""}
  end

  test "before_delete and after_delete with model" do
    model = %AllCallback{id: 1, x: "x"}
    model = MockRepo.delete model
    assert model.before == %{}
    assert model.after == %{}
  end

  test "before_insert and after_insert with changeset" do
    changeset = Ecto.Changeset.cast(%{"y" => "y", "z" => "z"},
                                    %AllCallback{x: "x", y: "z"}, ~w(y z), ~w())
    model = MockRepo.insert changeset
    assert model.before == %{x: "x", y: "y", z: "z"}
    assert model.after == %{x: "x", y: "y"}
    assert model.x == "x"
    assert model.y == "y"
    assert model.z == ""
  end

  test "before_update and after_update with changeset" do
    changeset = Ecto.Changeset.cast(%{"y" => "y", "z" => "z"},
                                    %AllCallback{id: 1, x: "x", y: "z"}, ~w(y z), ~w())
    model = MockRepo.update changeset
    assert model.before == %{y: "y", z: "z"}
    assert model.after == %{y: "y"}
    assert model.x == "x"
    assert model.y == "y"
    assert model.z == ""
  end
end
