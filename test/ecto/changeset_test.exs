defmodule Ecto.ChangesetTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset

  defmodule Post do
    use Ecto.Model

    schema "posts" do
      field :title
      field :body
    end
  end

  ## cast/4

  test "cast/4: on success" do
    params = %{"title" => "hello", "body" => "world"}
    struct = %Post{}

    changeset = cast(params, struct, ~w(title), ~w(body))
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{title: "hello", body: "world"}
    assert changeset.errors == []
    assert changeset.validations == [title: :required]
    assert changeset.valid?
  end

  test "cast/4: missing optional" do
    params = %{"title" => "hello"}
    struct = %Post{}

    changeset = cast(params, struct, ~w(title), ~w(body))
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{title: "hello"}
    assert changeset.errors == []
    assert changeset.validations == [title: :required]
    assert changeset.valid?
  end

  test "cast/4: missing required" do
    params = %{"body" => "world"}
    struct = %Post{}

    changeset = cast(params, struct, ~w(title), ~w(body))
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{body: "world"}
    assert changeset.errors == [title: :blank]
    assert changeset.validations == [title: :required]
    refute changeset.valid?
  end

  test "cast/4: can't cast required field" do
    params = %{"body" => :world}
    struct = %Post{}

    changeset = cast(params, struct, ~w(body), ~w())
    assert changeset.changes == %{}
    assert changeset.errors == [body: :invalid]
    refute changeset.valid?
  end

  test "cast/4: can't cast optional field" do
    params = %{"body" => :world}
    struct = %Post{}

    changeset = cast(params, struct, ~w(), ~w(body))
    assert changeset.changes == %{}
    assert changeset.errors == [body: :invalid]
    refute changeset.valid?
  end

  test "cast/4: blank errors" do
    for title <- [nil, "", "   "] do
      changeset = cast(%{"title" => title}, %Post{}, ~w(title), ~w())
      assert changeset.errors == [title: :blank]
      refute changeset.valid?
    end

    for title <- [nil, "", "   "] do
      changeset = cast(%{}, %Post{title: title}, ~w(title), ~w())
      assert changeset.errors == [title: :blank]
      refute changeset.valid?
    end

    for title <- [nil, "", "   "] do
      changeset = cast(%{"title" => title}, %Post{title: "valid"}, ~w(title), ~w())
      assert changeset.errors == [title: :blank]
      refute changeset.valid?
    end
  end

  test "cast/4: is not blank if model is correct" do
    changeset = cast(%{}, %Post{title: "valid"}, ~w(title), ~w())
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "cast/4: fails on invalid field" do
    assert_raise ArgumentError, "unknown field `unknown`", fn ->
      cast(%{}, %Post{}, ~w(), ~w(unknown))
    end

    assert_raise ArgumentError, "unknown field `unknown`", fn ->
      cast(%{}, %Post{}, ~w(unknown), ~w())
    end
  end
end