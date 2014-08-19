defmodule Ecto.Model.AssignTest do
  use ExUnit.Case, async: true

  defmodule User do
    use Ecto.Model

    schema "users" do
      field :name, :string, default: "eric"
      field :email, :string, default: "eric@email"
      field :temp, :virtual, default: "temp"
      field :array, {:array, :string}
    end
  end

  test "assigning returns the correct struct" do
    assert %User{} = Ecto.Model.assign(User, %{})
    assert %User{} = Ecto.Model.assign(%User{}, %{})
  end

  test "assigns with strings as keys" do
    assert Ecto.Model.assign(User, %{"name" => "martin"}).name == "martin"
    assert Ecto.Model.assign(%User{}, %{"name" => "martin"}).name == "martin"
  end

  test "assigns with atoms as keys" do
    assert Ecto.Model.assign(User, %{name: "martin"}).name == "martin"
    assert Ecto.Model.assign(%User{}, %{name: "martin"}).name == "martin"
  end

  test "assigns with both atoms and strings as keys" do
    user = Ecto.Model.assign(User, %{:name => "martin", "email" => "martin@email"})
    assert user.name == "martin"
    assert user.email == "martin@email"

    user = Ecto.Model.assign(%User{}, %{:name => "martin", "email" => "martin@email"})
    assert user.name == "martin"
    assert user.email == "martin@email"
  end

  test "assigning honors defaults for absent values" do
    user = Ecto.Model.assign(User, %{name: "martin"})
    assert user.name == "martin"
    assert user.email == "eric@email"

    user = Ecto.Model.assign(%User{}, %{name: "martin"})
    assert user.name == "martin"
    assert user.email == "eric@email"
  end

  test "discards keys that don't correspond to a field" do
    assert_raise KeyError, fn -> Ecto.Model.assign(User, %{"blafoo" => "martin"}).blafoo end
    assert_raise KeyError, fn -> Ecto.Model.assign(%User{}, %{"blafoo" => "martin"}).blafoo end
  end

  test "restricts assignment to given keys if :only option is used" do
    user = Ecto.Model.assign(User, %{:name => "martin", "email" => "martin@email"}, only: [:email])
    assert user.name == "eric"
    assert user.email == "martin@email"
  end

  test "keeps existing entries even if key is restricted with :only option" do
    user = Ecto.Model.assign(%User{name: "martin"}, %{name: "not martin", email: "martin@email"}, only: [:email])
    assert user.name == "martin"
    assert user.email == "martin@email"
  end
end
