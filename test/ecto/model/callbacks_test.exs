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

  test "stores callbacks in the model's __callbacks__" do
    assert User.__callbacks__(:before_insert) == [{Utils, :set_timestamps}]
  end

  test "stores multiple callbacks in the model's __callbacks__" do
    assert Enum.count(User.__callbacks__(:before_update)) == 2
  end

  test "returns empty lists for non-registered callbacks" do
    assert Enum.empty? User.__callbacks__(:before_delete)
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

    after_get __MODULE__, :send_after_get

    def test_send(message, model), do: send(self, {message, model})
    def send_after_get(model), do: test_send(:after_get, model)
  end

  defmodule MockAdapter do
    @behaviour Ecto.Adapter

    defmacro __using__(_opts), do: :ok
    def start_link(_repo, _opts), do: :ok
    def stop(_repo), do: :ok
    def all(_repo, _query, _opts), do: [%CallbackModel{id: 1}]
    def insert(_repo, record, _opts) do
      record.id(45)
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

  test "before_get" do
    MyRepo.get CallbackModel, 1

    assert_received {:after_get, %CallbackModel{id: _}}
  end
end
