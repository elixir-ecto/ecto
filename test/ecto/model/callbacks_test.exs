defmodule Ecto.Model.CallbacksTest do
  use ExUnit.Case, async: true

  defmodule User do
    use Ecto.Model

    schema "users" do
      field :name

      field :created_at
      field :updated_at
    end

    callbacks do
      on :before_save,   &User.set_updated_at/1
      on :before_insert, &User.set_updated_at/1
      on :before_insert, &User.set_created_at/1
    end

    def set_updated_at(user), do: %{ user | updated_at: Ecto.DateTime.local }
    def set_created_at(user), do: %{ user | created_at: Ecto.DateTime.local }
  end


  test "stores callbacks in the model's __callbacks__" do
    assert is_function List.first(User.__callbacks__(:before_save))
  end

  test "stores multiple callbacks in the model's __callbacks__" do
    assert Enum.count(User.__callbacks__(:before_insert)) == 2
  end

  test "returns empty lists for non-registered callbacks" do
    assert Enum.empty? User.__callbacks__(:before_delete)
  end

  test "applies callbacks" do

    assert %User{name: "Michael"}
            |> Ecto.Model.Callbacks.apply_callbacks(:before_save) ==
              %User{name: "Michael", updated_at: Ecto.DateTime.local }
  end

  test "applies multiple callbcaks" do
    assert %User{name: "Michael"}
            |> Ecto.Model.Callbacks.apply_callbacks(:before_insert) ==
              %User{name: "Michael", updated_at: Ecto.DateTime.local,
                    created_at: Ecto.DateTime.local }
  end
end
