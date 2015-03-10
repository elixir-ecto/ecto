defmodule Ecto.ChangesetTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset

  defmodule Post do
    use Ecto.Model

    schema "posts" do
      field :title
      field :body
      field :upvotes, :integer
    end
  end

  defp changeset(params, model \\ %Post{}) do
    cast(model, params, ~w(), ~w(title body upvotes))
  end

  ## cast/4

  test "cast/4: with valid string keys" do
    params = %{"title" => "hello", "body" => "world"}
    struct = %Post{}

    changeset = cast(struct, params, ~w(title)a, ~w(body))
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{title: "hello", body: "world"}
    assert changeset.errors == []
    assert changeset.validations == []
    assert changeset.required == [:title]
    assert changeset.optional == [:body]
    assert changeset.valid?
  end

  test "cast/4: with valid atom keys" do
    params = %{title: "hello", body: "world"}
    struct = %Post{}

    changeset = cast(struct, params, ~w(title)a, ~w(body))
    assert changeset.params == %{"title" => "hello", "body" => "world"}
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

    changeset = cast(struct, params, ~w(title), ~w(body))
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{title: "hello"}
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "cast/4: no optionals passed is valid" do
    params = %{"title" => "hello"}
    struct = %Post{}

    changeset = cast(struct, params, ~w(title))
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{title: "hello"}
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "cast/4: missing required is invalid" do
    params = %{"body" => "world"}
    struct = %Post{}

    changeset = cast(struct, params, ~w(title), ~w(body))
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{body: "world"}
    assert changeset.errors == [title: :required]
    refute changeset.valid?
  end

  test "cast/4: no parameters is invalid" do
    changeset = cast(%Post{}, nil, ~w(title), ~w(body)a)
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

    changeset = cast(struct, params, ~w(body), ~w())
    assert changeset.changes == %{}
    assert changeset.errors == [body: :invalid]
    refute changeset.valid?
  end

  test "cast/4: can't cast optional field" do
    params = %{"body" => :world}
    struct = %Post{}

    changeset = cast(struct, params, ~w(), ~w(body))
    assert changeset.changes == %{}
    assert changeset.errors == [body: :invalid]
    refute changeset.valid?
  end

  test "cast/4: required errors" do
    changeset = cast(%Post{}, %{"title" => nil}, ~w(title), ~w())
    assert changeset.errors == [title: :required]
    refute changeset.valid?

    changeset = cast(%Post{title: nil}, %{}, ~w(title), ~w())
    assert changeset.errors == [title: :required]
    refute changeset.valid?

    changeset = cast(%Post{title: "valid"}, %{"title" => nil}, ~w(title), ~w())
    assert changeset.errors == [title: :required]
    refute changeset.valid?
  end

  test "cast/4: does not mark as required if model contains field" do
    changeset = cast(%Post{title: "valid"}, %{}, ~w(title), ~w())
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "cast/4: fails on invalid field" do
    assert_raise ArgumentError, "unknown field `unknown`", fn ->
      cast(%Post{}, %{}, ~w(), ~w(unknown))
    end

    assert_raise ArgumentError, "unknown field `unknown`", fn ->
      cast(%Post{}, %{}, ~w(unknown), ~w())
    end
  end

  test "cast/4: fails on bad arguments" do
    assert_raise ArgumentError, ~r"expected params to be a map, got struct", fn ->
      cast(%Post{}, %Post{}, ~w(), ~w(unknown))
    end

    assert_raise ArgumentError, ~r"mixed keys", fn ->
      cast(%Post{}, %{"title" => "foo", title: "foo"}, ~w(), ~w(unknown))
    end

    assert_raise FunctionClauseError, fn ->
      cast(%Post{}, [], ~w(), ~w(unknown))
    end
  end

  test "cast/4: works with a changeset as the second argument" do
    base_changeset = cast(%Post{title: "valid"}, %{}, ~w(title), ~w())

    # No changes
    changeset = cast(base_changeset, %{}, ~w(), ~w())
    assert changeset.valid?
    assert changeset.changes  == %{}
    assert changeset.required == [:title]

    changeset = cast(base_changeset, %{body: "new body"}, ~w(), ~w(body))
    assert changeset.valid?
    assert changeset.changes  == %{body: "new body"}
    assert changeset.required == [:title]
    assert changeset.optional == [:body]
  end

  ## Changeset functions

  test "merge/2: merges changes, errors and validations" do
    # Changes
    cs1 = cast(%Post{}, %{title: "foo"}, ~w(title), ~w())
    cs2 = cast(%Post{}, %{body: "bar"}, ~w(body), ~w())
    assert merge(cs1, cs2).changes == %{body: "bar", title: "foo"}

    # Errors
    cs1 = cast(%Post{}, %{}, ~w(title), ~w())
    cs2 = cast(%Post{}, %{}, ~w(title body), ~w())
    changeset = merge(cs1, cs2)
    refute changeset.valid?
    assert Enum.sort(changeset.errors) == [body: :required, title: :required, title: :required]

    # Validations
    cs1 = cast(%Post{}, %{title: "Title"}, ~w(title), ~w())
                |> validate_length(:title, 1..10)

    cs2 = cast(%Post{}, %{body: "Body"}, ~w(body), ~w())
                |> validate_format(:body, ~r/B/)

    changeset = merge(cs1, cs2)
    assert changeset.valid?
    assert length(changeset.validations) == 2
    assert Enum.find(changeset.validations, &match?({:body, {:format, _}}, &1))
    assert Enum.find(changeset.validations, &match?({:title, {:length, _}}, &1))
  end

  test "merge/2: gives required fields precedence over optional ones" do
    cs1 = cast(%Post{}, %{}, ~w(title), ~w())
    cs2 = cast(%Post{}, %{}, ~w(), ~w(title))
    changeset = merge(cs1, cs2)
    assert changeset.required == [:title]
    assert changeset.optional == []
  end

  test "merge/2: doesn't duplicate required or optional fields" do
    cs1 = cast(%Post{}, %{}, ~w(title body), ~w())
    cs2 = cast(%Post{}, %{}, ~w(body title), ~w(title))
    changeset = merge(cs1, cs2)
    assert Enum.sort(changeset.required) == [:body, :title]
    assert Enum.sort(changeset.optional) == []
  end

  test "merge/2: gives precedence to the second changeset" do
    cs1 = cast(%Post{}, %{title: "foo"}, ~w(title), ~w())
    cs2 = cast(%Post{}, %{title: "bar"}, ~w(title), ~w())
    changeset = merge(cs1, cs2)
    assert changeset.valid?
    assert changeset.params == %{"title" => "bar"}
    assert changeset.changes == %{title: "bar"}
  end

  test "merge/2: merges the :repo field when either one is nil" do
    changeset = merge(%Ecto.Changeset{repo: :foo}, %Ecto.Changeset{repo: nil})
    assert changeset.repo == :foo

    changeset = merge(%Ecto.Changeset{repo: nil}, %Ecto.Changeset{repo: :bar})
    assert changeset.repo == :bar
  end

  test "merge/2: fails when the :model or :repo field are not equal" do
    cs1 = cast(%Post{title: "foo"}, %{}, ~w(title), ~w())
    cs2 = cast(%Post{title: "bar"}, %{}, ~w(title), ~w())
    assert_raise ArgumentError, "different models when merging changesets", fn ->
      merge(cs1, cs2)
    end
    assert_raise ArgumentError, "different repos when merging changesets", fn ->
      merge(%Ecto.Changeset{repo: :foo}, %Ecto.Changeset{repo: :bar})
    end
  end

  test "change/2 with a model" do
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

  test "change/2 with a changeset" do
    base_changeset = cast(%Post{}, %{title: "title"}, ~w(title), ~w())

    assert change(base_changeset) == base_changeset

    changeset = change(base_changeset, %{body: "body"})
    assert changeset.changes == %{title: "title", body: "body"}

    changeset = change(base_changeset, %{title: "new title"})
    assert changeset.changes == %{title: "new title"}

    changeset = change(base_changeset, title: "new title")
    assert changeset.changes == %{title: "new title"}
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

  test "put_new_change/3" do
    changeset = changeset(%{})

    changeset = put_change(changeset, :title, "foo")
    assert changeset.changes.title == "foo"

    changeset = put_new_change(changeset, :title, "bar")
    assert changeset.changes.title == "foo"

    changeset = put_new_change(changeset, :body, "body")
    assert changeset.changes.body == "body"
  end

  test "apply/1" do
    post = %Post{}
    assert post.title == nil

    changeset = changeset(%{"title" => "foo"}, post)
    changed_post = apply(changeset)

    assert changed_post.__struct__ == post.__struct__
    assert changed_post.title == "foo"
  end

  ## Validations

  test "add_error/3" do
    changeset =
      changeset(%{})
      |> add_error(:foo, {:bar, nil})
    assert changeset.errors == [foo: [bar: nil]]

    # Add another error to foo
    changeset =
      changeset
      |> add_error(:foo, {:baz, nil})
    assert changeset.errors == [foo: [baz: nil, bar: nil]]

    # Add a single error to bar
    changeset =
      changeset
      |> add_error(:bar, {:foo, nil})
    assert changeset.errors == [
      foo: [
        baz: nil,
        bar: nil
      ],
      bar: [
        foo: nil
      ]
    ]
  end

  test "add_errors/3" do
    changeset =
      changeset(%{})
      |> add_errors(:foo, [{:bar, nil}, {:baz, "qux"}])
    assert changeset.errors == [foo: [bar: nil, baz: "qux"]]
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
      |> validate_change(:title, fn :title, "hello" -> [{:oops, nil}] end)

    refute changeset.valid?
    assert changeset.errors == [title: [oops: nil]]

    # When invalid with multiple errors
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_change(:title, fn :title, "hello" -> [{:oops, nil}, {:norf, nil}] end)

    refute changeset.valid?
    assert changeset.errors == [title: [oops: nil, norf: nil]]

    # When missing
    changeset =
      changeset(%{})
      |> validate_change(:title, fn :title, "hello" -> [{:oops, nil}] end)

    assert changeset.valid?
    assert changeset.errors == []

    # When nil
    changeset =
      changeset(%{"title" => nil})
      |> validate_change(:title, fn :title, "hello" -> [{:oops, nil}] end)

    assert changeset.valid?
    assert changeset.errors == []
  end

  test "validate_change/4" do
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_change(:title, :oops, fn :title, "hello" -> [{:oops, nil}] end)

    refute changeset.valid?
    assert changeset.errors == [title: [oops: nil]]
    assert changeset.validations == [title: :oops]

    changeset =
      changeset(%{})
      |> validate_change(:title, :oops, fn :title, "hello" -> [{:oops, nil}] end)

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
    assert changeset.errors == [title: [must_have_format: ~r/@/]]
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
    assert changeset.errors == [title: [must_include: ["world"]]]
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
    assert changeset.errors == [title: [must_exclude: ["world"]]]
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
    assert changeset.errors == [title: [must_be_unique: nil]]
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
    assert changeset.errors == [title: [must_be_longer_than: 6]]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, 1..4)
    refute changeset.valid?
    assert changeset.errors == [title: [must_be_shorter_than: 4]]
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
    assert changeset.errors == [title: [must_be_longer_than: 6]]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, max: 4)
    refute changeset.valid?
    assert changeset.errors == [title: [must_be_shorter_than: 4]]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, is: 10)
    refute changeset.valid?
    assert changeset.errors == [title: [must_be_length: 10]]
  end

  test "validate_number/3" do
    # single validation
    changeset =
      changeset(%{"upvotes" => 3})
      |> validate_number(:upvotes, greater_than: 0)
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [upvotes: {:number, [greater_than: 0]}]

    # single error
    changeset =
      changeset(%{"upvotes" => -1})
      |> validate_number(:upvotes, greater_than: 0)
    refute changeset.valid?
    assert changeset.errors == [upvotes: [must_be_greater_than: 0]]
    assert changeset.validations == [upvotes: {:number, [greater_than: 0]}]

    # multiple validations
    changeset =
      changeset(%{"upvotes" => 3})
      |> validate_number(:upvotes, greater_than: 0, less_than: 100)
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [upvotes: {:number, [greater_than: 0, less_than: 100]}]

    # multiple validations with multiple errors
    changeset =
      changeset(%{"upvotes" => 3})
      |> validate_number(:upvotes, less_than: 0, greater_than: 100)
    refute changeset.valid?
    assert changeset.errors == [
      upvotes: [
        must_be_less_than: 0,
        must_be_greater_than: 100
      ]
    ]
    assert changeset.validations == [upvotes: {:number, [less_than: 0, greater_than: 100]}]
  end
end
