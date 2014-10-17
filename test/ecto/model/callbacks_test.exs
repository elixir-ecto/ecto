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
end
