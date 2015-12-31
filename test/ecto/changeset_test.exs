defmodule Ecto.ChangesetTest do
  use ExUnit.Case, async: true
  import Ecto.Changeset

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      belongs_to :post, Ecto.ChangesetTest.Post
    end
  end

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field :title
      field :body
      field :uuid, :binary_id
      field :decimal, :decimal
      field :upvotes, :integer, default: 0
      field :topics, {:array, :string}
      field :published_at, Ecto.DateTime
      has_many :comments, Ecto.ChangesetTest.Comment
      has_one :comment, Ecto.ChangesetTest.Comment
    end
  end

  defp changeset(model \\ %Post{}, params) do
    cast(model, params, ~w(), ~w(title body upvotes topics decimal))
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
    assert changeset.valid?
  end

  test "cast/4: with binary id" do
    changeset = cast(%Post{}, %{"uuid" => "hello"}, [:uuid], [])
    assert changeset.changes == %{uuid: "hello"}
    assert changeset.errors == []
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

    changeset = cast(struct, params, ~w(title), [])
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{title: "hello"}
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "cast/4: missing required is invalid" do
    params = %{"body" => "world"}
    struct = %Post{}

    changeset = cast(struct, params, ~w(title upvotes), ~w(body))
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{body: "world"}
    assert changeset.errors == [title: "can't be blank"]
    refute changeset.valid?
  end

  test "cast/4: empty parameters is invalid" do
    changeset = cast(%Post{}, :empty, ~w(title), ~w(body)a)
    assert changeset.model == %Post{}
    assert changeset.params == nil
    assert changeset.changes == %{}
    assert changeset.errors == []
    assert changeset.validations == []
    assert changeset.required == [:title]
    refute changeset.valid?
  end

  test "cast/4: can't cast required field is marked as invalid" do
    params = %{"body" => :world}
    struct = %Post{}

    changeset = cast(struct, params, ~w(body), ~w())
    assert changeset.changes == %{}
    assert changeset.errors == [body: "is invalid"]
    refute changeset.valid?
  end

  test "cast/4: can't cast optional field is marked as invalid" do
    params = %{"body" => :world}
    struct = %Post{}

    changeset = cast(struct, params, ~w(), ~w(body))
    assert changeset.changes == %{}
    assert changeset.errors == [body: "is invalid"]
    refute changeset.valid?
  end

  test "cast/4: required errors" do
    changeset = cast(%Post{}, %{"title" => nil}, ~w(title), ~w())
    assert changeset.errors == [title: "can't be blank"]
    assert changeset.changes == %{}
    refute changeset.valid?

    changeset = cast(%Post{title: nil}, %{}, ~w(title), ~w())
    assert changeset.errors == [title: "can't be blank"]
    assert changeset.changes == %{}
    refute changeset.valid?

    changeset = cast(%Post{title: "valid"}, %{"title" => nil}, ~w(title), ~w())
    assert changeset.errors == [title: "can't be blank"]
    assert changeset.changes == %{}
    refute changeset.valid?
  end

  test "cast/4: does not mark as required if model contains field" do
    changeset = cast(%Post{title: "valid"}, %{}, ~w(title), ~w())
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "cast/4: does not mark as required if changes contains field" do
    changeset = cast(%Post{}, %{title: "valid"}, ~w(title), ~w())
    changeset = cast(changeset, %{}, ~w(title), ~w())
    assert changeset.changes == %{title: "valid"}
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "cast/4: fails on invalid field" do
    assert_raise ArgumentError, ~r"unknown field `unknown`", fn ->
      cast(%Post{}, %{}, ~w(), ~w(unknown))
    end

    assert_raise ArgumentError, ~r"unknown field `unknown`", fn ->
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

  test "cast/4: works when casting a changeset" do
    base_changeset = cast(%Post{title: "valid"}, %{}, ~w(title), ~w())
                     |> validate_length(:title, min: 3)
                     |> unique_constraint(:title)

    # No changes
    changeset = cast(base_changeset, %{}, ~w(), ~w())
    assert changeset.valid?
    assert changeset.changes  == %{}
    assert changeset.required == [:title]
    assert length(changeset.validations) == 1
    assert length(changeset.constraints) == 1

    changeset = cast(base_changeset, %{body: "new body"}, ~w(), ~w(body))
    assert changeset.valid?
    assert changeset.changes  == %{body: "new body"}
    assert changeset.required == [:title]
    assert length(changeset.validations) == 1
    assert length(changeset.constraints) == 1
  end

  test "cast/4: works when casting a changeset with empty parameters" do
    changeset = cast(%Post{}, %{"title" => "sample"}, ~w(title)a, ~w())
    changeset = cast(changeset, :empty, ~w(), ~w(body)a)
    assert changeset.model == %Post{}
    assert changeset.params == %{"title" => "sample"}
    assert changeset.changes == %{title: "sample"}
    assert changeset.errors == []
    assert changeset.validations == []
    assert changeset.required == [:title]
    refute changeset.valid?
  end

  test "cast/4: works on casting a datetime field" do
    date = %Ecto.DateTime{year: 2015, month: 5, day: 1, hour: 10, min: 8, sec: 0}
    params = %{"published_at" => date}
    struct = %Post{}

    changeset = cast(struct, params, ~w(published_at), ~w())
    assert changeset.params == params
    assert changeset.model  == struct
    assert changeset.changes == %{published_at: date}
    assert changeset.valid?
  end

  test "cast/4: protects against atom injection" do
    assert_raise ArgumentError, fn ->
      cast(%Post{}, %{}, ~w(surely_never_saw_this_atom_before), [])
    end
  end

  ## Changeset functions

  test "merge/2: merges changes" do
    cs1 = cast(%Post{}, %{title: "foo"}, ~w(title), ~w())
    cs2 = cast(%Post{}, %{body: "bar"}, ~w(body), ~w())
    assert merge(cs1, cs2).changes == %{body: "bar", title: "foo"}

    cs1 = cast(%Post{}, %{title: "foo"}, ~w(title), ~w())
    cs2 = cast(%Post{}, %{title: "bar"}, ~w(title), ~w())
    changeset = merge(cs1, cs2)
    assert changeset.valid?
    assert changeset.params == %{"title" => "bar"}
    assert changeset.changes == %{title: "bar"}
  end

  test "merge/2: merges errors" do
    cs1 = cast(%Post{}, %{}, ~w(title), ~w())
    cs2 = cast(%Post{}, %{}, ~w(title body), ~w())
    changeset = merge(cs1, cs2)
    refute changeset.valid?
    assert changeset.errors ==
           [title: "can't be blank", body: "can't be blank"]
  end

  test "merge/2: merges validations" do
    cs1 = cast(%Post{}, %{title: "Title"}, ~w(title), ~w())
                |> validate_length(:title, min: 1, max: 10)
    cs2 = cast(%Post{}, %{body: "Body"}, ~w(body), ~w())
                |> validate_format(:body, ~r/B/)

    changeset = merge(cs1, cs2)
    assert changeset.valid?
    assert length(changeset.validations) == 2
    assert Enum.find(changeset.validations, &match?({:body, {:format, _}}, &1))
    assert Enum.find(changeset.validations, &match?({:title, {:length, _}}, &1))
  end

  test "merge/2: merges constraints" do
    cs1 = cast(%Post{}, %{title: "Title"}, ~w(title), ~w())
                |> unique_constraint(:title)
    cs2 = cast(%Post{}, %{body: "Body"}, ~w(body), ~w())
                |> unique_constraint(:body)

    changeset = merge(cs1, cs2)
    assert changeset.valid?
    assert length(changeset.constraints) == 2
  end

  test "merge/2: merges parameters" do
    empty = cast(%Post{}, :empty, ~w(title), ~w())
    cs1   = cast(%Post{}, %{body: "foo"}, ~w(body), ~w())
    cs2   = cast(%Post{}, %{body: "bar"}, ~w(body), ~w())
    assert merge(cs1, cs2).params == %{"body" => "bar"}

    assert merge(cs1, empty).params == %{"body" => "foo"}
    assert merge(empty, cs2).params == %{"body" => "bar"}
    assert merge(empty, empty).params == nil
  end

  test "merge/2: gives required fields precedence over optional ones" do
    cs1 = cast(%Post{}, %{}, ~w(title), ~w())
    cs2 = cast(%Post{}, %{}, ~w(), ~w(title))
    changeset = merge(cs1, cs2)
    assert changeset.required == [:title]
  end

  test "merge/2: doesn't duplicate required or optional fields" do
    cs1 = cast(%Post{}, %{}, ~w(title body), ~w())
    cs2 = cast(%Post{}, %{}, ~w(body title), ~w(title))
    changeset = merge(cs1, cs2)
    assert Enum.sort(changeset.required) == [:body, :title]
  end

  test "merge/2: merges the :repo field when either one is nil" do
    changeset = merge(%Ecto.Changeset{repo: :foo}, %Ecto.Changeset{repo: nil})
    assert changeset.repo == :foo

    changeset = merge(%Ecto.Changeset{repo: nil}, %Ecto.Changeset{repo: :bar})
    assert changeset.repo == :bar
  end

  test "merge/2: merges the :action field when either one is nil" do
    changeset = merge(%Ecto.Changeset{action: :insert}, %Ecto.Changeset{repo: nil})
    assert changeset.action == :insert

    changeset = merge(%Ecto.Changeset{action: nil}, %Ecto.Changeset{action: :update})
    assert changeset.action == :update
  end

  test "merge/2: fails when the :model, :repo or :action field are not equal" do
    cs1 = cast(%Post{title: "foo"}, %{}, ~w(title), ~w())
    cs2 = cast(%Post{title: "bar"}, %{}, ~w(title), ~w())

    assert_raise ArgumentError, "different models when merging changesets", fn ->
      merge(cs1, cs2)
    end

    assert_raise ArgumentError, "different repos (`:foo` and `:bar`) when merging changesets", fn ->
      merge(%Ecto.Changeset{repo: :foo}, %Ecto.Changeset{repo: :bar})
    end

    assert_raise ArgumentError, "different actions (`:insert` and `:update`) when merging changesets", fn ->
      merge(%Ecto.Changeset{action: :insert}, %Ecto.Changeset{action: :update})
    end
  end

  test "change/2 with a model" do
    changeset = change(%Post{})
    assert changeset.valid?
    assert changeset.model == %Post{}
    assert changeset.changes == %{}

    changeset = change(%Post{body: "bar"}, body: "bar")
    assert changeset.valid?
    assert changeset.model == %Post{body: "bar"}
    assert changeset.changes == %{}

    changeset = change(%Post{body: "bar"}, %{body: "bar", title: "foo"})
    assert changeset.valid?
    assert changeset.model == %Post{body: "bar"}
    assert changeset.changes == %{title: "foo"}

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
    base_changeset = cast(%Post{upvotes: 5}, %{title: "title"}, ~w(title), ~w())

    assert change(base_changeset) == base_changeset

    changeset = change(base_changeset, %{body: "body"})
    assert changeset.changes == %{title: "title", body: "body"}

    changeset = change(base_changeset, %{title: "new title"})
    assert changeset.changes == %{title: "new title"}

    changeset = change(base_changeset, title: "new title")
    assert changeset.changes == %{title: "new title"}

    changeset = change(base_changeset, title: nil)
    assert changeset.changes == %{}

    changeset = change(base_changeset, %{upvotes: nil})
    assert changeset.changes == %{title: "title", upvotes: nil}

    changeset = change(base_changeset, %{upvotes: 5})
    assert changeset.changes == %{title: "title"}

    changeset = change(base_changeset, %{upvotes: 10})
    assert changeset.changes == %{title: "title", upvotes: 10}

    changeset = change(base_changeset, %{title: "new title", upvotes: 5})
    assert changeset.changes == %{title: "new title"}
  end

  test "fetch_field/2" do
    changeset = changeset(%Post{body: "bar"}, %{"title" => "foo"})

    assert fetch_field(changeset, :title) == {:changes, "foo"}
    assert fetch_field(changeset, :body) == {:model, "bar"}
    assert fetch_field(changeset, :other) == :error
  end

  test "get_field/3" do
    changeset = changeset(%Post{body: "bar"}, %{"title" => "foo"})

    assert get_field(changeset, :title) == "foo"
    assert get_field(changeset, :body) == "bar"
    assert get_field(changeset, :body, "other") == "bar"
    assert get_field(changeset, :other) == nil
    assert get_field(changeset, :other, "other") == "other"
  end

  test "fetch_change/2" do
    changeset = changeset(%{"title" => "foo", "body" => nil, "upvotes" => nil})

    assert fetch_change(changeset, :title) == {:ok, "foo"}
    assert fetch_change(changeset, :body) == :error
    assert fetch_change(changeset, :upvotes) == {:ok, nil}
  end

  test "get_change/3" do
    changeset = changeset(%{"title" => "foo", "body" => nil, "upvotes" => nil})

    assert get_change(changeset, :title) == "foo"
    assert get_change(changeset, :body) == nil
    assert get_change(changeset, :body, "other") == "other"
    assert get_change(changeset, :upvotes) == nil
    assert get_change(changeset, :upvotes, "other") == nil
  end

  test "update_change/3" do
    changeset =
      changeset(%{"title" => "foo"})
      |> update_change(:title, & &1 <> "bar")
    assert changeset.changes.title == "foobar"

    changeset =
      changeset(%{"upvotes" => nil})
      |> update_change(:upvotes, & &1 || 10)
    assert changeset.changes.upvotes == 10

    changeset =
      changeset(%{})
      |> update_change(:title, & &1 || "bar")
    assert changeset.changes == %{}
  end

  test "put_change/3 and delete_change/2" do
    base_changeset = change(%Post{upvotes: 5})

    changeset = put_change(base_changeset, :title, "foo")
    assert changeset.changes.title == "foo"

    changeset = delete_change(changeset, :title)
    assert changeset.changes == %{}

    changeset = put_change(base_changeset, :title, "bar")
    assert changeset.changes.title == "bar"

    changeset = put_change(base_changeset, :title, nil)
    assert changeset.changes == %{}

    changeset = put_change(base_changeset, :upvotes, 5)
    assert changeset.changes == %{}

    changeset = put_change(changeset, :upvotes, 10)
    assert changeset.changes.upvotes == 10

    changeset = put_change(base_changeset, :upvotes, nil)
    assert changeset.changes.upvotes == nil
  end

  test "force_change/3" do
    changeset = change(%Post{upvotes: 5})

    changeset = force_change(changeset, :title, "foo")
    assert changeset.changes.title == "foo"

    changeset = force_change(changeset, :title, "bar")
    assert changeset.changes.title == "bar"

    changeset = force_change(changeset, :upvotes, 5)
    assert changeset.changes.upvotes == 5
  end

  test "apply_changes/1" do
    post = %Post{}
    assert post.title == nil

    changeset = changeset(post, %{"title" => "foo"})
    changed_post = apply_changes(changeset)

    assert changed_post.__struct__ == post.__struct__
    assert changed_post.title == "foo"
  end

  ## Validations

  test "add_error/3" do
    changeset =
      changeset(%{})
      |> add_error(:foo, "bar")
    assert changeset.errors == [foo: "bar"]
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
      |> validate_change(:title, fn :title, "hello" -> [title: "oops"] end)

    refute changeset.valid?
    assert changeset.errors == [title: "oops"]

    # When missing
    changeset =
      changeset(%{})
      |> validate_change(:title, fn :title, "hello" -> [title: "oops"] end)

    assert changeset.valid?
    assert changeset.errors == []

    # When nil
    changeset =
      changeset(%{"title" => nil})
      |> validate_change(:title, fn :title, "hello" -> [title: "oops"] end)

    assert changeset.valid?
    assert changeset.errors == []
  end

  test "validate_change/4" do
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_change(:title, :oops, fn :title, "hello" -> [title: "oops"] end)

    refute changeset.valid?
    assert changeset.errors == [title: "oops"]
    assert changeset.validations == [title: :oops]

    changeset =
      changeset(%{})
      |> validate_change(:title, :oops, fn :title, "hello" -> [title: "oops"] end)

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
    assert changeset.errors == [title: "has invalid format"]
    assert changeset.validations == [title: {:format, ~r/@/}]

    changeset =
      changeset(%{"title" => "foobar"})
      |> validate_format(:title, ~r/@/, message: "yada")
    assert changeset.errors == [title: "yada"]
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
    assert changeset.errors == [title: "is invalid"]
    assert changeset.validations == [title: {:inclusion, ~w(world)}]

    changeset =
      changeset(%{"title" => "hello"})
      |> validate_inclusion(:title, ~w(world), message: "yada")
    assert changeset.errors == [title: "yada"]
  end

  test "validate_subset/3" do
    changeset =
      changeset(%{"topics" => ["cat", "dog"]})
      |> validate_subset(:topics, ~w(cat dog))
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [topics: {:subset, ~w(cat dog)}]

    changeset =
      changeset(%{"topics" => ["cat", "laptop"]})
      |> validate_subset(:topics, ~w(cat dog))
    refute changeset.valid?
    assert changeset.errors == [topics: "has an invalid entry"]
    assert changeset.validations == [topics: {:subset, ~w(cat dog)}]

    changeset =
      changeset(%{"topics" => ["laptop"]})
      |> validate_subset(:topics, ~w(cat dog), message: "yada")
    assert changeset.errors == [topics: "yada"]
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
    assert changeset.errors == [title: "is reserved"]
    assert changeset.validations == [title: {:exclusion, ~w(world)}]

    changeset =
      changeset(%{"title" => "world"})
      |> validate_exclusion(:title, ~w(world), message: "yada")
    assert changeset.errors == [title: "yada"]
  end

  test "validate_length/3 with string" do
    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, min: 3, max: 7)
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [title: {:length, [min: 3, max: 7]}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, min: 5, max: 5)
    assert changeset.valid?

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, is: 5)
    assert changeset.valid?

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, min: 6)
    refute changeset.valid?
    assert changeset.errors == [title: {"should be at least %{count} character(s)", count: 6}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, max: 4)
    refute changeset.valid?
    assert changeset.errors == [title: {"should be at most %{count} character(s)", count: 4}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, is: 10)
    refute changeset.valid?
    assert changeset.errors == [title: {"should be %{count} character(s)", count: 10}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, is: 10, message: "yada")
    assert changeset.errors == [title: {"yada", count: 10}]
  end

  test "validate_length/3 with list" do
    changeset = changeset(%{"topics" => ["Politics", "Security", "Economy", "Elections"]}) |> validate_length(:topics, min: 3, max: 7)
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [topics: {:length, [min: 3, max: 7]}]

    changeset = changeset(%{"topics" => ["Politics", "Security"]}) |> validate_length(:topics, min: 2, max: 2)
    assert changeset.valid?

    changeset = changeset(%{"topics" => ["Politics", "Security", "Economy"]}) |> validate_length(:topics, is: 3)
    assert changeset.valid?

    changeset = changeset(%{"topics" => ["Politics", "Security"]}) |> validate_length(:topics, min: 6, foo: true)
    refute changeset.valid?
    assert changeset.errors == [topics: {"should have at least %{count} item(s)", count: 6}]

    changeset = changeset(%{"topics" => ["Politics", "Security", "Economy"]}) |> validate_length(:topics, max: 2)
    refute changeset.valid?
    assert changeset.errors == [topics: {"should have at most %{count} item(s)", count: 2}]

    changeset = changeset(%{"topics" => ["Politics", "Security"]}) |> validate_length(:topics, is: 10)
    refute changeset.valid?
    assert changeset.errors == [topics: {"should have %{count} item(s)", count: 10}]

    changeset = changeset(%{"topics" => ["Politics", "Security"]}) |> validate_length(:topics, is: 10, message: "yada")
    assert changeset.errors == [topics: {"yada", count: 10}]
  end

  test "validate_number/3" do
    changeset = changeset(%{"upvotes" => 3})
                |> validate_number(:upvotes, greater_than: 0)
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [upvotes: {:number, [greater_than: 0]}]

    # Single error
    changeset = changeset(%{"upvotes" => -1})
                |> validate_number(:upvotes, greater_than: 0)
    refute changeset.valid?
    assert changeset.errors == [upvotes: {"must be greater than %{count}", count: 0}]
    assert changeset.validations == [upvotes: {:number, [greater_than: 0]}]

    # Multiple validations
    changeset = changeset(%{"upvotes" => 3})
                |> validate_number(:upvotes, greater_than: 0, less_than: 100)
    assert changeset.valid?
    assert changeset.errors == []
    assert changeset.validations == [upvotes: {:number, [greater_than: 0, less_than: 100]}]

    # Multiple validations with multiple errors
    changeset = changeset(%{"upvotes" => 3})
                |> validate_number(:upvotes, greater_than: 100, less_than: 0)
    refute changeset.valid?
    assert changeset.errors == [upvotes: {"must be greater than %{count}", count: 100}]

    # Multiple validations with custom message errors
    changeset = changeset(%{"upvotes" => 3})
                |> validate_number(:upvotes, greater_than: 100, less_than: 0, message: "yada")
    assert changeset.errors == [upvotes: {"yada", count: 100}]
  end

  test "validate_number/3 with decimal" do
    changeset = changeset(%{"decimal" => Decimal.new(1)})
                |> validate_number(:decimal, greater_than: Decimal.new(-3))
    assert changeset.valid?

    changeset = changeset(%{"decimal" => Decimal.new(-3)})
                |> validate_number(:decimal, less_than: Decimal.new(1))
    assert changeset.valid?

    changeset = changeset(%{"decimal" => Decimal.new(-1)})
                |> validate_number(:decimal, equal_to: Decimal.new(-1))
    assert changeset.valid?

    changeset = changeset(%{"decimal" => Decimal.new(-3)})
                |> validate_number(:decimal, less_than_or_equal_to: Decimal.new(-1))
    assert changeset.valid?
    changeset = changeset(%{"decimal" => Decimal.new(-3)})
                |> validate_number(:decimal, less_than_or_equal_to: Decimal.new(-3))
    assert changeset.valid?

    changeset = changeset(%{"decimal" => Decimal.new(-1)})
                |> validate_number(:decimal, greater_than_or_equal_to: Decimal.new(-1.5))
    assert changeset.valid?
    changeset = changeset(%{"decimal" => Decimal.new(1.5)})
                |> validate_number(:decimal, greater_than_or_equal_to: Decimal.new(1.5))
    assert changeset.valid?
  end

  test "validate_number/3 with bad options" do
    assert_raise ArgumentError, "unknown option :min given to validate_number/3", fn  ->
      validate_number(changeset(%{"upvotes" => 1}), :upvotes, min: Decimal.new(1.5))
    end
  end

  test "validate_confirmation/3" do
    changeset = changeset(%{"title" => "title", "title_confirmation" => "title"})
                |> validate_confirmation(:title)
    assert changeset.valid?
    assert changeset.errors == []

    changeset = changeset(%{"title" => "title", "title_confirmation" => nil})
                |> validate_confirmation(:title)
    refute changeset.valid?
    assert changeset.errors == [title_confirmation: "does not match confirmation"]

    changeset = changeset(%{"title" => "title", "title_confirmation" => "not title"})
                |> validate_confirmation(:title)
    refute changeset.valid?
    assert changeset.errors == [title_confirmation: "does not match confirmation"]

    changeset = changeset(%{"title" => "title", "title_confirmation" => "not title"})
                |> validate_confirmation(:title, message: "doesn't match field below")
    refute changeset.valid?
    assert changeset.errors == [title_confirmation: "doesn't match field below"]

    # Skip when no parameter
    changeset = changeset(%{"title" => "title"})
                |> validate_confirmation(:title, message: "password doesn't match")
    assert changeset.valid?
    assert changeset.errors == []

    # With casting
    changeset = changeset(%{"upvotes" => "1", "upvotes_confirmation" => "1"})
                |> validate_confirmation(:upvotes)
    assert changeset.valid?
    assert changeset.errors == []
  end

  ## Locks

  test "optimistic_lock/3 with changeset" do
    changeset = changeset(%{}) |> optimistic_lock(:upvotes)
    assert changeset.filters == %{upvotes: 0}
    assert changeset.changes == %{upvotes: 1}
  end

  test "optimistic_lock/3 with model" do
    changeset = %Post{} |> optimistic_lock(:upvotes)
    assert changeset.filters == %{upvotes: 0}
    assert changeset.changes == %{upvotes: 1}
  end

  test "optimistic_lock/3 with custom incrementer" do
    changeset = %Post{} |> optimistic_lock(:upvotes, &(&1 - 1))
    assert changeset.filters == %{upvotes: 0}
    assert changeset.changes == %{upvotes: -1}
  end

  ## Constraints

  test "unique_constraint/3" do
    changeset = change(%Post{}) |> unique_constraint(:title)
    assert changeset.constraints ==
           [%{type: :unique, field: :title, constraint: "posts_title_index",
              message: "has already been taken"}]

    changeset = change(%Post{}) |> unique_constraint(:title, name: :whatever, message: "is taken")
    assert changeset.constraints ==
           [%{type: :unique, field: :title, constraint: "whatever", message: "is taken"}]
  end

  test "foreign_key_constraint/3" do
    changeset = change(%Comment{}) |> foreign_key_constraint(:post_id)
    assert changeset.constraints ==
           [%{type: :foreign_key, field: :post_id, constraint: "comments_post_id_fkey",
              message: "does not exist"}]

    changeset = change(%Comment{}) |> foreign_key_constraint(:post_id, name: :whatever, message: "is not available")
    assert changeset.constraints ==
           [%{type: :foreign_key, field: :post_id, constraint: "whatever", message: "is not available"}]
  end

  test "assoc_constraint/3" do
    changeset = change(%Comment{}) |> assoc_constraint(:post)
    assert changeset.constraints ==
           [%{type: :foreign_key, field: :post, constraint: "comments_post_id_fkey",
              message: "does not exist"}]

    changeset = change(%Comment{}) |> assoc_constraint(:post, name: :whatever, message: "is not available")
    assert changeset.constraints ==
           [%{type: :foreign_key, field: :post, constraint: "whatever", message: "is not available"}]
  end

  test "assoc_constraint/3 with errors" do
    message = ~r"cannot add constraint to changeset because association `unknown` does not exist"
    assert_raise ArgumentError, message, fn ->
      change(%Post{}) |> assoc_constraint(:unknown)
    end

    message = ~r"assoc_constraint can only be added to belongs to associations"
    assert_raise ArgumentError, message, fn ->
      change(%Post{}) |> assoc_constraint(:comments)
    end
  end

  test "no_assoc_constraint/3 with has_many" do
    changeset = change(%Post{}) |> no_assoc_constraint(:comments)
    assert changeset.constraints ==
           [%{type: :foreign_key, field: :comments, constraint: "comments_post_id_fkey",
              message: "are still associated to this entry"}]

    changeset = change(%Post{}) |> no_assoc_constraint(:comments, name: :whatever, message: "exists")
    assert changeset.constraints ==
           [%{type: :foreign_key, field: :comments, constraint: "whatever", message: "exists"}]
  end

  test "no_assoc_constraint/3 with has_one" do
    changeset = change(%Post{}) |> no_assoc_constraint(:comment)
    assert changeset.constraints ==
           [%{type: :foreign_key, field: :comment, constraint: "comments_post_id_fkey",
              message: "is still associated to this entry"}]

    changeset = change(%Post{}) |> no_assoc_constraint(:comment, name: :whatever, message: "exists")
    assert changeset.constraints ==
           [%{type: :foreign_key, field: :comment, constraint: "whatever", message: "exists"}]
  end

  test "no_assoc_constraint/3 with errors" do
    message = ~r"cannot add constraint to changeset because association `unknown` does not exist"
    assert_raise ArgumentError, message, fn ->
      change(%Post{}) |> no_assoc_constraint(:unknown)
    end

    message = ~r"no_assoc_constraint can only be added to has one/many associations"
    assert_raise ArgumentError, message, fn ->
      change(%Comment{}) |> no_assoc_constraint(:post)
    end
  end

  test "exclude_constraint/3" do
    changeset = change(%Post{}) |> exclude_constraint(:title)
    assert changeset.constraints ==
           [%{type: :exclude, field: :title, constraint: "posts_title_exclusion",
              message: "violates an exclusion constraint"}]

    changeset = change(%Post{}) |> exclude_constraint(:title, name: :whatever, message: "is invalid")
    assert changeset.constraints ==
           [%{type: :exclude, field: :title, constraint: "whatever", message: "is invalid"}]
  end

  ## traverse_errors

  test "traverses changeset errors" do
    changeset =
      changeset(%{"title" => "title", "body" => "hi"})
      |> validate_length(:body, min: 3)
      |> validate_format(:body, ~r/888/)
      |> add_error(:title, "is taken")

    errors = traverse_errors(changeset, fn
      {err, opts} ->
        err
        |> String.replace("%{count}", to_string(opts[:count]))
        |> String.upcase()
      err -> String.upcase(err)
    end)

    assert errors == %{
      body: ["HAS INVALID FORMAT", "SHOULD BE AT LEAST 3 CHARACTER(S)"],
      title: ["IS TAKEN"]
    }
  end

  ## inspect

  test "inspects relevant data" do
    assert inspect(%Ecto.Changeset{}) ==
           "#Ecto.Changeset<action: nil, changes: %{}, errors: [], model: nil, valid?: false>"

    assert inspect(changeset(%{"title" => "title", "body" => "hi"})) ==
           "#Ecto.Changeset<action: nil, changes: %{body: \"hi\", title: \"title\"}, " <>
           "errors: [], model: #Ecto.ChangesetTest.Post<>, valid?: true>"
  end
end
