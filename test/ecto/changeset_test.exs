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

  defp changeset(params, model \\ %Post{}) do
    cast(params, model, ~w(), ~w(title body))
  end

  ## cast/4

  test "cast/4: on success is valid" do
    params = %{"title" => "hello", "body" => "world"}
    struct = %Post{}

    changeset = cast(params, struct, ~w(title)a, ~w(body))
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{title: "hello", body: "world"}
    assert changeset.errors == []
    assert changeset.validations == []
    assert changeset.required == [:title]
    assert changeset.optional == [:body]
    assert changeset.valid?
  end

  test "cast/4: missing optional is valid" do
    params = %{"title" => "hello"}
    struct = %Post{}

    changeset = cast(params, struct, ~w(title), ~w(body))
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{title: "hello"}
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "cast/4: no optionals passed is valid" do
    params = %{"title" => "hello"}
    struct = %Post{}

    changeset = cast(params, struct, ~w(title))
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{title: "hello"}
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "cast/4: missing required is invalid" do
    params = %{"body" => "world"}
    struct = %Post{}

    changeset = cast(params, struct, ~w(title), ~w(body))
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{body: "world"}
    assert changeset.errors == [title: :required]
    refute changeset.valid?
  end

  test "cast/4: no parameters is invalid" do
    changeset = cast(nil, %Post{}, ~w(title), ~w(body)a)
    assert changeset.model == %Post{}
    assert changeset.params == nil
    assert changeset.changes == %{}
    assert changeset.errors == []
    assert changeset.validations == []
    assert changeset.required == [:title]
    assert changeset.optional == [:body]
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
      assert changeset.errors == [title: :required]
      refute changeset.valid?
    end

    for title <- [nil, "", "   "] do
      changeset = cast(%{}, %Post{title: title}, ~w(title), ~w())
      assert changeset.errors == [title: :required]
      refute changeset.valid?
    end

    for title <- [nil, "", "   "] do
      changeset = cast(%{"title" => title}, %Post{title: "valid"}, ~w(title), ~w())
      assert changeset.errors == [title: :required]
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

  ## Changeset functions

  test "change/2" do
    changeset = change(%Post{})
    assert changeset.valid?
    assert changeset.model == %Post{}
    assert changeset.changes == %{}

    changeset = change(%Post{}, body: "bar")
    assert changeset.valid?
    assert changeset.model == %Post{}
    assert changeset.changes == %{body: "bar"}

    changeset = change(%Post{}, %{body: "bar"})
    assert changeset.valid?
    assert changeset.model == %Post{}
    assert changeset.changes == %{body: "bar"}
  end

  test "fetch_field/2" do
    changeset = changeset(%{"title" => "foo"}, %Post{body: "bar"})

    assert fetch_field(changeset, :title) == {:changes, "foo"}
    assert fetch_field(changeset, :body) == {:model, "bar"}
    assert fetch_field(changeset, :other) == :error
  end

  test "get_field/3" do
    changeset = changeset(%{"title" => "foo"}, %Post{body: "bar"})

    assert get_field(changeset, :title) == "foo"
    assert get_field(changeset, :body) == "bar"
    assert get_field(changeset, :body, "other") == "bar"
    assert get_field(changeset, :other) == nil
    assert get_field(changeset, :other, "other") == "other"
  end

  test "fetch_change/2" do
    changeset = changeset(%{"title" => "foo", "body" => nil})

    assert fetch_change(changeset, :title) == {:ok, "foo"}
    assert fetch_change(changeset, :body) == {:ok, nil}
    assert fetch_change(changeset, :other) == :error
  end

  test "get_change/3" do
    changeset = changeset(%{"title" => "foo", "body" => nil})

    assert get_change(changeset, :title) == "foo"
    assert get_change(changeset, :body) == nil
    assert get_change(changeset, :body, "other") == nil
    assert get_change(changeset, :other) == nil
    assert get_change(changeset, :other, "other") == "other"
  end

  test "update_change/3" do
    changeset =
      changeset(%{"title" => "foo"})
      |> update_change(:title, & &1 <> "bar")
    assert changeset.changes.title == "foobar"

    changeset =
      changeset(%{"title" => nil})
      |> update_change(:title, & &1 || "bar")
    assert changeset.changes.title == "bar"

    changeset =
      changeset(%{})
      |> update_change(:title, & &1 || "bar")
    assert changeset.changes == %{}
  end

  test "put_change/3 and delete_change/2" do
    changeset = changeset(%{})

    changeset = put_change(changeset, :title, "foo")
    assert changeset.changes.title == "foo"

    changeset = put_change(changeset, :title, "bar")
    assert changeset.changes.title == "bar"

    changeset = delete_change(changeset, :title)
    assert changeset.changes == %{}
  end

  ## Validations

  test "add_error/3" do
    changeset =
      changeset(%{})
      |> add_error(:foo, :bar)
    assert changeset.errors == [foo: :bar]
  end

  test "validate_change/3" do
    # When valid
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_change(:title, fn :title, "hello" -> [] end)

    assert changeset.valid?
    assert changeset.errors == []

    # When invalid
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_change(:title, fn :title, "hello" -> [{:title, :oops}] end)

    refute changeset.valid?
    assert changeset.errors == [title: :oops]

    # When missing
    changeset =
      changeset(%{})
      |> validate_change(:title, fn :title, "hello" -> [{:title, :oops}] end)

    assert changeset.valid?
    assert changeset.errors == []

    # When nil
    changeset =
      changeset(%{"title" => nil})
      |> validate_change(:title, fn :title, "hello" -> [{:title, :oops}] end)

    assert changeset.valid?
    assert changeset.errors == []
  end

  test "validate_change/4" do
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_change(:title, :oops, fn :title, "hello" -> [{:title, :oops}] end)

    refute changeset.valid?
    assert changeset.errors == [title: :oops]
    assert changeset.validations == [title: :oops]

    changeset =
      changeset(%{})
      |> validate_change(:title, :oops, fn :title, "hello" -> [{:title, :oops}] end)

    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [title: :oops]
  end

  test "validate_format/3" do
    changeset =
      changeset(%{"title" => "foo@bar"})
      |> validate_format(:title, ~r/@/)
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [title: {:format, ~r/@/}]

    changeset =
      changeset(%{"title" => "foobar"})
      |> validate_format(:title, ~r/@/)
    refute changeset.valid?
    assert changeset.errors == [title: :format]
    assert changeset.validations == [title: {:format, ~r/@/}]
  end

  test "validate_inclusion/3" do
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_inclusion(:title, ~w(hello))
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [title: {:inclusion, ~w(hello)}]

    changeset =
      changeset(%{"title" => "hello"})
      |> validate_inclusion(:title, ~w(world))
    refute changeset.valid?
    assert changeset.errors == [title: :inclusion]
    assert changeset.validations == [title: {:inclusion, ~w(world)}]
  end

  test "validate_exclusion/3" do
    changeset =
      changeset(%{"title" => "world"})
      |> validate_exclusion(:title, ~w(hello))
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [title: {:exclusion, ~w(hello)}]

    changeset =
      changeset(%{"title" => "world"})
      |> validate_exclusion(:title, ~w(world))
    refute changeset.valid?
    assert changeset.errors == [title: :exclusion]
    assert changeset.validations == [title: {:exclusion, ~w(world)}]
  end

  test "validate_unique/3" do
    defmodule UniqueRepo do
      def all(query) do
        [where] = query.wheres
        assert Macro.to_string(where.expr) == "&0.title() == ^0"
        assert query.limit.expr == 1
        Process.get(:unique_query)
      end
    end

    Process.put(:unique_query, [])
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_unique(:title, on: UniqueRepo)
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [title: :unique]

    Process.put(:unique_query, [1])
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_unique(:title, on: UniqueRepo)
    refute changeset.valid?
    assert changeset.errors == [title: :unique]
    assert changeset.validations == [title: :unique]
  end

  test "validate_unique/3 with primary key" do
    defmodule UniquePKRepo do
      def all(query) do
        [where, pk_where] = query.wheres
        assert Macro.to_string(where.expr) == "&0.title() == ^0"
        assert Macro.to_string(pk_where.expr) == "&0.id() != ^0"
        []
      end
    end

    changeset =
      changeset(%{"title" => "hello"}, %Post{id: 1})
      |> validate_unique(:title, on: UniquePKRepo)
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [title: :unique]
  end

  test "validate_unique/3 with downcase" do
    defmodule DowncaseRepo do
      def all(query) do
        [where] = query.wheres
        assert Macro.to_string(where.expr) ==
               ~s|fragment("lower(", &0.title(), ")") == fragment("lower(", ^0, ")")|
        []
      end
    end

    changeset =
      changeset(%{"title" => "hello"})
      |> validate_unique(:title, on: DowncaseRepo, downcase: true)
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [title: :unique]
  end

  test "validate_length/3 with range" do
    changeset =
      changeset(%{"title" => "world"})
      |> validate_length(:title, 3..7)
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [title: {:length, [min: 3, max: 7]}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, 5..5)
    assert changeset.valid?

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, 6..10)
    refute changeset.valid?
    assert changeset.errors == [title: {:too_short, 6}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, 1..4)
    refute changeset.valid?
    assert changeset.errors == [title: {:too_long, 4}]
  end

  test "validate_length/3 with option" do
    changeset =
      changeset(%{"title" => "world"})
      |> validate_length(:title, min: 3, max: 7)
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [title: {:length, [min: 3, max: 7]}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, min: 5, max: 5)
    assert changeset.valid?

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, is: 5)
    assert changeset.valid?

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, min: 6)
    refute changeset.valid?
    assert changeset.errors == [title: {:too_short, 6}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, max: 4)
    refute changeset.valid?
    assert changeset.errors == [title: {:too_long, 4}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, is: 10)
    refute changeset.valid?
    assert changeset.errors == [title: {:wrong_length, 10}]
  end
end
