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

  test "all possible macros are there" do
    assert macro_exported?(Ecto.Model.Callbacks, :before_insert, 2)
    assert macro_exported?(Ecto.Model.Callbacks, :after_insert, 2)
    assert macro_exported?(Ecto.Model.Callbacks, :before_update, 2)
    assert macro_exported?(Ecto.Model.Callbacks, :after_update, 2)
    assert macro_exported?(Ecto.Model.Callbacks, :before_delete, 2)
    assert macro_exported?(Ecto.Model.Callbacks, :after_delete, 2)
  end

  test "defines functions for callbacks" do
    assert function_exported?(User, :before_insert, 1)
  end

  test "doesn't define callbacks for not-registered events" do
    refute function_exported?(User, :after_insert, 1)
  end

  test "applies callbacks" do
    assert %User{name: "Michael"}
            |> Ecto.Model.Callbacks.apply_callbacks(:before_insert) ==
              %User{name: "Michael", updated_at: Utils.current_time,
                    created_at: Utils.current_time}
  end

  test "applies multiple callbcaks" do
    assert %User{name: "Michael"}
            |> Ecto.Model.Callbacks.apply_callbacks(:before_update) ==
              %User{name: "Michael", updated_at: Utils.current_time,
                    created_at: Utils.current_time, revision: 1}
  end

  ## Repo integration

  defmodule CallbackModel do
    use Ecto.Model

    schema "callback_model" do
      field :x
    end

    before_update __MODULE__, :send_before_update

    def test_send(message, model), do: send(self, {message, model})
    def send_before_update(model), do: test_send(:before_update, model)
  end

  defmodule MockAdapter do
    @behaviour Ecto.Adapter

    defmacro __using__(_opts), do: :ok
    def start_link(_repo, _opts), do: :ok
    def stop(_repo), do: :ok
    def all(_repo, _query, _opts), do: [%CallbackModel{id: 1}]
    def insert(_repo, record, _opts) do
      %{ record | id: 45 }
    end
    def update(_repo, _record, _opts), do: 1
    def update_all(_repo, _query, _values, _external, _opts), do: 1
    def delete(_repo, _record, _opts), do: 1
    def delete_all(_repo, _query, _opts), do: 1
  end

  defmodule MyRepo do
    use Ecto.Repo, adapter: MockAdapter

    def conf, do: []
    def priv, do: app_dir(:ecto, "priv/db")
    def url,  do: parse_url("ecto://user@localhost/db")
  end

  test "before_update" do
    MyRepo.update %CallbackModel{id: 1, x: "foo"}

    assert_received {:before_update, _}
  end
end
