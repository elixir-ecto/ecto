Code.require_file "../../support/mock_repo.exs", __DIR__
alias Ecto.MockRepo

defmodule Ecto.Model.CallbacksTest do
  use ExUnit.Case, async: true

  defmodule UpdateCallback do
    use Ecto.Model

    schema "update_callback" do
      field :x, :string, default: ""
    end

    before_update __MODULE__, :add_before
    before_update __MODULE__, :add_before

    def add_before(model), do: %{model | x: model.x <> ",before"}
  end

  test "defines functions for callbacks" do
    assert function_exported?(UpdateCallback, :before_update, 1)
  end

  test "doesn't define callbacks for not-registered events" do
    refute function_exported?(UpdateCallback, :after_update, 1)
  end

  test "applies multiple callbacks" do
    assert Ecto.Model.Callbacks.__apply__(%UpdateCallback{x: "initial"}, :before_update) ==
           %UpdateCallback{x: "initial,before,before"}
  end

  ## Repo integration

  defmodule AllCallback do
    use Ecto.Model

    schema "all_callback" do
      field :x, :string, default: ""
    end

    before_insert __MODULE__, :add_before
    after_insert  __MODULE__, :add_after
    before_update __MODULE__, :add_before
    after_update  __MODULE__, :add_after
    before_delete __MODULE__, :add_before
    after_delete  __MODULE__, :add_after

    def add_before(model), do: %{model | x: model.x <> ",before"}
    def add_after(model),  do: %{model | x: model.x <> ",after"}
  end

  test "wraps operations into transactions if callback present" do
    model = %UpdateCallback{x: "initial"}
    MockRepo.insert model
    refute_received {:transaction, _fun}

    model = %AllCallback{x: "initial"}
    MockRepo.insert model
    assert_received {:transaction, _fun}
  end

  test "before_insert and after_insert" do
    model = %AllCallback{x: "initial"}
    model = MockRepo.insert model
    assert model.x == "initial,before,after"
  end

  test "before_update and after_update" do
    model = %AllCallback{id: 1, x: "initial"}
    model = MockRepo.update model
    assert model.x == "initial,before,after"
  end

  test "before_delete and after_delete" do
    model = %AllCallback{id: 1, x: "initial"}
    model = MockRepo.update model
    assert model.x == "initial,before,after"
  end
end
