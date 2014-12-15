defmodule Ecto.Model.CallbacksTest do
  use ExUnit.Case, async: true

  defmodule Utils do
    @current_time Ecto.DateTime.local

    def set_timestamps(model) do
      %{ model |
        created_at: model.created_at || @current_time,
        updated_at: @current_time
      }
    end

    def current_time, do: @current_time
  end

  defmodule User do
    use Ecto.Model

    schema "users" do
      field :name

      field :revision, :integer

      field :created_at, :datetime
      field :updated_at, :datetime
    end

    before_insert Utils, :set_timestamps
    before_update Utils, :set_timestamps
    before_update User, :incr_revision

    def incr_revision(user), do: %{ user | revision: (user.revision || 0) + 1}
  end

  test "defines functions for callbacks" do
    assert function_exported?(User, :before_insert, 1)
  end

  test "doesn't define callbacks for not-registered events" do
    refute function_exported?(User, :after_insert, 1)
  end

  test "applies callbacks" do
    assert %User{name: "Michael"}
            |> Ecto.Model.Callbacks.__apply__(:before_insert) ==
              %User{name: "Michael", updated_at: Utils.current_time,
                    created_at: Utils.current_time}
  end

  test "applies multiple callbacks" do
    assert %User{name: "Michael"}
            |> Ecto.Model.Callbacks.__apply__(:before_update) ==
              %User{name: "Michael", updated_at: Utils.current_time,
                    created_at: Utils.current_time, revision: 1}
  end

  ## Repo integration

  defmodule CallbackModel do
    use Ecto.Model

    schema "callback_model" do
      field :x
    end

    before_insert __MODULE__, :add_before_insert
    after_insert __MODULE__, :add_after_insert
    before_update __MODULE__, :send_before_update
    after_update __MODULE__, :send_after_update
    before_delete __MODULE__, :send_before_delete
    after_delete __MODULE__, :send_after_delete

    def add_before_insert(model), do: %{model | x: model.x <> ",before_insert"}
    def add_after_insert(model), do: %{model | x: model.x <> ",after_insert"}
    def send_before_update(model) do
      send(self, {:before_update, model})
      %{model | x: "changed before update"}
    end
    def send_after_update(model), do: send(self, {:after_update, model})
    def send_before_delete(model) do
      send(self, {:before_delete, model})
      %{model | x: "changed before delete"}
    end
    def send_after_delete(model), do: send(self, {:after_delete, model})
  end

  defmodule MockRepo do
    use Ecto.Repo, adapter: Ecto.MockAdapter

    def conf, do: []
    def priv, do: app_dir(:ecto, "priv/db")
    def url,  do: parse_url("ecto://user@localhost/db")
  end

  test "wraps operations into transactions if callback present" do
    model = %CallbackModel{id: 1, x: "initial"}

    MockRepo.insert model

    # From MockAdapter:
    assert_received {:transaction, _fun}
  end

  test "before_insert, after_insert" do
    model = %CallbackModel{id: 1, x: "initial"}

    model = MockRepo.insert model

    assert model.x == "initial,before_insert,after_insert"
  end

  test "before_update" do
    model = %CallbackModel{id: 1, x: "foo"}

    MockRepo.update  model

    assert_received {:before_update, ^model}
    # From MockAdapter:
    assert_received {:update, %CallbackModel{id: 1, x: "changed before update"}}
  end

  test "after_update" do
    model = %CallbackModel{id: 1, x: "foo"}

    MockRepo.update  model

    model_after_update = %{model | x: "changed before update"}

    assert_received {:after_update, ^model_after_update}
  end

  test "before_delete" do
    model = %CallbackModel{id: 1, x: "foo"}

    MockRepo.delete model

    assert_received {:before_delete, ^model}
    # From MockAdapter:
    assert_received {:delete, %CallbackModel{id: 1, x: "changed before delete"}}
  end

  test "after_delete" do
    model = %CallbackModel{id: 1, x: "foo"}

    MockRepo.delete model

    model_after_delete = %{model | x: "changed before delete"}

    assert_received {:after_delete, ^model_after_delete}
  end
end
