defmodule Ecto.ChangesetTest do
  use ExUnit.Case, async: true
  import Ecto.Changeset

  defmodule SocialSource do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :origin
      field :url
    end

    def changeset(schema \\ %SocialSource{}, params) do
      cast(schema, params, ~w(origin url)a)
    end
  end

  defmodule Category do
    use Ecto.Schema

    schema "categories" do
      field :name, :string
      has_many :posts, Ecto.ChangesetTest.Post
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      belongs_to :post, Ecto.ChangesetTest.Post
    end
  end

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field :token, :integer, primary_key: true
      field :title, :string, default: ""
      field :body
      field :uuid, :binary_id
      field :color, :binary
      field :decimal, :decimal
      field :upvotes, :integer, default: 0
      field :topics, {:array, :string}
      field :virtual, :string, virtual: true
      field :published_at, :naive_datetime
      field :source, :map
      field :permalink, :string, source: :url
      belongs_to :category, Ecto.ChangesetTest.Category, source: :cat_id
      has_many :comments, Ecto.ChangesetTest.Comment, on_replace: :delete
      has_one :comment, Ecto.ChangesetTest.Comment
    end
  end

  defp changeset(schema \\ %Post{}, params) do
    cast(schema, params, ~w(id token title body upvotes decimal color topics virtual)a)
  end

  defmodule CustomError do
    use Ecto.Type
    def type,      do: :any
    def cast(_),   do: {:error, message: "custom error message", reason: :foobar}
    def load(_),   do: :error
    def dump(_),   do: :error
  end

  defmodule CustomErrorWithType do
    use Ecto.Type
    def type,      do: :any
    def cast(_),   do: {:error, message: "custom error message", reason: :foobar, type: :some_type}
    def load(_),   do: :error
    def dump(_),   do: :error
  end

  defmodule CustomErrorWithoutMessage do
    use Ecto.Type
    def type,      do: :any
    def cast(_),   do: {:error, reason: :foobar}
    def load(_),   do: :error
    def dump(_),   do: :error
  end

  defmodule CustomErrorTest do
    use Ecto.Schema

    schema "custom_error" do
      field :custom_error, CustomError
      field :custom_error_without_message, CustomErrorWithoutMessage
      field :custom_error_with_type, CustomErrorWithType
      field :array_custom_error, {:array, CustomError}
      field :map_custom_error, {:map, CustomError}
    end
  end

  ## cast/4
  test "cast/4: with valid string keys" do
    params = %{"title" => "hello", "body" => "world"}
    struct = %Post{}

    changeset = cast(struct, params, ~w(title body)a)
    assert changeset.params == params
    assert changeset.data  == struct
    assert changeset.changes == %{title: "hello", body: "world"}
    assert changeset.errors == []
    assert validations(changeset) == []
    assert changeset.required == []
    assert changeset.valid?
  end

  test "cast/4: with valid atom keys" do
    params = %{title: "hello", body: "world"}
    struct = %Post{}

    changeset = cast(struct, params, ~w(title body)a)
    assert changeset.params == %{"title" => "hello", "body" => "world"}
    assert changeset.data  == struct
    assert changeset.changes == %{title: "hello", body: "world"}
    assert changeset.errors == []
    assert validations(changeset) == []
    assert changeset.required == []
    assert changeset.valid?
  end

  test "cast/4: with empty values" do
    params = %{"title" => "", "body" => nil}
    struct = %Post{title: "foo", body: "bar"}

    changeset = cast(struct, params, ~w(title body)a)
    assert changeset.changes == %{title: "", body: nil}
  end

  test "cast/4: with custom empty values" do
    params = %{"title" => "empty", "body" => nil}
    struct = %Post{title: "foo", body: "bar"}

    changeset = cast(struct, params, ~w(title body)a, empty_values: ["empty"])
    assert changeset.changes == %{title: "", body: nil}
    assert changeset.empty_values == ["empty"]
  end

  test "cast/4: with matching empty values" do
    params = %{"title" => "", "body" => nil}
    struct = %Post{title: "", body: nil}

    changeset = cast(struct, params, ~w(title body)a)
    assert changeset.changes == %{}
  end

  test "cast/4: with data and types" do
    data   = {%{title: "hello"}, %{title: :string, upvotes: :integer}}
    params = %{"title" => "world", "upvotes" => "0"}

    changeset = cast(data, params, ~w(title upvotes)a)
    assert changeset.params == params
    assert changeset.data  == %{title: "hello"}
    assert changeset.changes == %{title: "world", upvotes: 0}
    assert changeset.errors == []
    assert changeset.valid?
    assert apply_changes(changeset) == %{title: "world", upvotes: 0}
  end

  test "cast/4: with dynamic embed" do
    data = {
      %{
        title: "hello"
      },
      %{
        title: :string,
        source: {
          :embed,
          %Ecto.Embedded{
            cardinality: :one,
            field: :source,
            on_cast: &SocialSource.changeset(&1, &2),
            on_replace: :raise,
            owner: nil,
            related: SocialSource,
            unique: true
          }
        }
      }
    }

    params = %{"title" => "world", "source" => %{"origin" => "facebook", "url" => "http://example.com/social"}}

    changeset =
      data
      |> cast(params, ~w(title)a)
      |> cast_embed(:source, required: true)

    assert changeset.params == params
    assert changeset.data  == %{title: "hello"}
    assert %{title: "world", source: %Ecto.Changeset{}} = changeset.changes
    assert changeset.errors == []
    assert changeset.valid?
    assert apply_changes(changeset) ==
      %{title: "world", source: %Ecto.ChangesetTest.SocialSource{origin: "facebook", url: "http://example.com/social"}}
  end

  test "cast/4: with changeset" do
    base_changeset = cast(%Post{title: "valid"}, %{}, ~w(title)a)
                     |> validate_required(:title)
                     |> validate_length(:title, min: 3)
                     |> unique_constraint(:title)

    # No changes
    changeset = cast(base_changeset, %{}, ~w())
    assert changeset.valid?
    assert changeset.changes  == %{}
    assert changeset.required == [:title]
    assert length(validations(changeset)) == 1
    assert length(constraints(changeset)) == 1

    # Value changes
    changeset = cast(changeset, %{body: "new body"}, ~w(body)a)
    assert changeset.valid?
    assert changeset.changes  == %{body: "new body"}
    assert changeset.required == [:title]
    assert length(validations(changeset)) == 1
    assert length(constraints(changeset)) == 1

    # Nil changes
    changeset = cast(changeset, %{body: nil}, ~w(body)a)
    assert changeset.valid?
    assert changeset.changes  == %{body: nil}
    assert changeset.required == [:title]
    assert length(validations(changeset)) == 1
    assert length(constraints(changeset)) == 1
  end

  test "cast/4: struct with :invalid parameters" do
    changeset = cast(%Post{}, :invalid, ~w(title body)a)
    assert changeset.data == %Post{}
    assert changeset.params == nil
    assert changeset.changes == %{}
    assert changeset.errors == []
    assert validations(changeset) == []
    refute changeset.valid?
  end

  test "cast/4: changeset with :invalid parameters" do
    changeset = cast(%Post{}, %{"title" => "sample"}, ~w(title)a)
    changeset = cast(changeset, :invalid, ~w(body)a)
    assert changeset.data == %Post{}
    assert changeset.params == %{"title" => "sample"}
    assert changeset.changes == %{title: "sample"}
    assert changeset.errors == []
    assert validations(changeset) == []
    refute changeset.valid?
  end

  test "cast/4: field is marked as invalid" do
    params = %{"body" => :world}
    struct = %Post{}

    changeset = cast(struct, params, ~w(body)a)
    assert changeset.changes == %{}
    assert changeset.errors == [body: {"is invalid", [type: :string, validation: :cast]}]
    refute changeset.valid?
  end

  test "cast/4: field has a custom invalid error message" do
    params = %{"custom_error" => :error}
    struct = %CustomErrorTest{}

    changeset = cast(struct, params, ~w(custom_error)a)
    assert changeset.errors == [custom_error: {"custom error message", [type: Ecto.ChangesetTest.CustomError, validation: :cast, reason: :foobar]}]
    refute changeset.valid?
  end

  test "cast/4: ignores the :type parameter in custom errors" do
    params = %{"custom_error_with_type" => :error}
    struct = %CustomErrorTest{}

    changeset = cast(struct, params, ~w(custom_error_with_type)a)
    assert changeset.errors == [custom_error_with_type: {"custom error message", [type: Ecto.ChangesetTest.CustomErrorWithType, validation: :cast, reason: :foobar]}]
    refute changeset.valid?
  end

  test "cast/4: field has a custom invalid error message without message" do
    params = %{"custom_error_without_message" => :error}
    struct = %CustomErrorTest{}

    changeset = cast(struct, params, ~w(custom_error_without_message)a)
    assert changeset.errors == [custom_error_without_message: {"is invalid", [type: Ecto.ChangesetTest.CustomErrorWithoutMessage, validation: :cast, reason: :foobar]}]
    refute changeset.valid?
  end

  test "cast/4: field has a custom invalid error message on an array field" do
    params = %{"array_custom_error" => [:error]}
    struct = %CustomErrorTest{}

    changeset = cast(struct, params, ~w(array_custom_error)a)
    assert changeset.errors == [array_custom_error: {"is invalid", [type: {:array, Ecto.ChangesetTest.CustomError}, validation: :cast]}]
    refute changeset.valid?
  end

  test "cast/4: field has a custom invalid error message on a map field" do
    params = %{"map_custom_error" => %{foo: :error}}
    struct = %CustomErrorTest{}

    changeset = cast(struct, params, ~w(map_custom_error)a)
    assert changeset.errors == [map_custom_error: {"is invalid", [type: {:map, Ecto.ChangesetTest.CustomError}, validation: :cast]}]
    refute changeset.valid?
  end

  test "cast/4: fails on invalid field" do
    assert_raise ArgumentError, ~r"unknown field `:unknown`", fn ->
      cast(%Post{}, %{}, ~w(unknown)a)
    end
  end

  test "cast/4: fails on bad arguments" do
    assert_raise Ecto.CastError, ~r"expected params to be a :map, got:", fn ->
      cast(%Post{}, %Post{}, ~w(unknown)a)
    end

    assert_raise Ecto.CastError, ~r"expected params to be a :map, got:", fn ->
      cast(%Post{}, "foo", ~w(unknown)a)
    end

    assert_raise Ecto.CastError, ~r"mixed keys", fn ->
      cast(%Post{}, %{"title" => "foo", title: "foo"}, ~w())
    end

    assert_raise FunctionClauseError, fn ->
      cast(%Post{}, %{}, %{})
    end

    assert_raise FunctionClauseError, fn ->
      cast(%Post{}, %{"title" => "foo"}, nil)
    end
  end

  test "cast/4: protects against atom injection" do
    assert_raise ArgumentError, fn ->
      cast(%Post{}, %{}, ~w(surely_never_saw_this_atom_before)a)
    end
  end

  test "cast/4: required field (via validate_required/2) of wrong type is marked as invalid" do
    params = %{"body" => :world}
    struct = %Post{}

    changeset = cast(struct, params, [:body])
                |> validate_required([:body])

    assert changeset.changes == %{}
    assert changeset.errors == [body: {"is invalid", [type: :string, validation: :cast]}]
    refute changeset.valid?
  end

  test "cast/4: does not validate types in data" do
    params = %{}
    struct = %Post{title: 100, decimal: "string"}

    changeset = cast(struct, params, ~w(title decimal)a)
    assert changeset.params == %{}
    assert changeset.data  == struct
    assert changeset.changes == %{}
    assert changeset.errors == []
    assert validations(changeset) == []
    assert changeset.required == []
    assert changeset.valid?
  end

  test "cast/4: semantic comparison" do
    changeset = cast(%Post{decimal: Decimal.new(1)}, %{decimal: "1.0"}, ~w(decimal)a)
    assert changeset.changes == %{}
    changeset = cast(%Post{decimal: Decimal.new(1)}, %{decimal: "1.1"}, ~w(decimal)a)
    assert changeset.changes == %{decimal: Decimal.new("1.1")}
    changeset = cast(%Post{decimal: nil}, %{decimal: nil}, ~w(decimal)a)
    assert changeset.changes == %{}

    {data, types} = {%{x: [Decimal.new(1)]}, %{x: {:array, :decimal}}}
    changeset = cast({data, types}, %{x: [Decimal.new("1.0")]}, ~w(x)a)
    assert changeset.changes == %{}
    changeset = cast({data, types}, %{x: [Decimal.new("1.1")]}, ~w(x)a)
    assert changeset.changes == %{x: [Decimal.new("1.1")]}
    changeset = cast({%{x: [nil]}, types}, %{x: [nil]}, ~w(x)a)
    assert changeset.changes == %{}

    {data, types} = {%{x: %{decimal: nil}}, %{x: {:map, :decimal}}}
    changeset = cast({data, types}, data, ~w(x)a)
    assert changeset.changes == %{}
  end

  ## Changeset functions

  test "merge/2: merges changes" do
    cs1 = cast(%Post{}, %{title: "foo"}, ~w(title)a)
    cs2 = cast(%Post{}, %{body: "bar"}, ~w(body)a)
    assert merge(cs1, cs2).changes == %{body: "bar", title: "foo"}

    cs1 = cast(%Post{}, %{title: "foo"}, ~w(title)a)
    cs2 = cast(%Post{}, %{title: "bar"}, ~w(title)a)
    changeset = merge(cs1, cs2)
    assert changeset.valid?
    assert changeset.params == %{"title" => "bar"}
    assert changeset.changes == %{title: "bar"}
  end

  test "merge/2: merges errors" do
    cs1 = cast(%Post{}, %{}, ~w(title)a) |> validate_required(:title)
    cs2 = cast(%Post{}, %{}, ~w(title body)a) |> validate_required([:title, :body])
    changeset = merge(cs1, cs2)
    refute changeset.valid?
    assert changeset.errors ==
           [title: {"can't be blank", [validation: :required]}, body: {"can't be blank", [validation: :required]}]
  end

  test "merge/2: merges validations" do
    cs1 = cast(%Post{}, %{title: "Title"}, ~w(title)a)
                |> validate_length(:title, min: 1, max: 10)
    cs2 = cast(%Post{}, %{body: "Body"}, ~w(body)a)
                |> validate_format(:body, ~r/B/)

    changeset = merge(cs1, cs2)
    assert changeset.valid?
    assert length(validations(changeset)) == 2
    assert Enum.find(validations(changeset), &match?({:body, {:format, _}}, &1))
    assert Enum.find(validations(changeset), &match?({:title, {:length, _}}, &1))
  end

  test "merge/2: repo opts" do
    cs1 = %Post{} |> change() |> Map.put(:repo_opts, [a: 1, b: 2])
    cs2 = %Post{} |> change() |> Map.put(:repo_opts, [b: 3, c: 4])
    changeset = merge(cs1, cs2)
    assert changeset.repo_opts == [a: 1, b: 3, c: 4]
  end

  test "merge/2: merges constraints" do
    cs1 = cast(%Post{}, %{title: "Title"}, ~w(title)a)
                |> unique_constraint(:title)
    cs2 = cast(%Post{}, %{body: "Body"}, ~w(body)a)
                |> unique_constraint(:body)

    changeset = merge(cs1, cs2)
    assert changeset.valid?
    assert length(constraints(changeset)) == 2
  end

  test "merge/2: merges parameters" do
    empty = cast(%Post{}, %{}, ~w(title)a)
    cs1   = cast(%Post{}, %{body: "foo"}, ~w(body)a)
    cs2   = cast(%Post{}, %{body: "bar"}, ~w(body)a)
    assert merge(cs1, cs2).params == %{"body" => "bar"}

    assert merge(cs1, empty).params == %{"body" => "foo"}
    assert merge(empty, cs2).params == %{"body" => "bar"}
    assert merge(empty, empty).params == %{}
  end

  test "merge/2: gives required fields precedence over optional ones" do
    cs1 = cast(%Post{}, %{}, ~w(title)a) |> validate_required(:title)
    cs2 = cast(%Post{}, %{}, ~w(title)a)
    changeset = merge(cs1, cs2)
    assert changeset.required == [:title]
  end

  test "merge/2: doesn't duplicate required or optional fields" do
    cs1 = cast(%Post{}, %{}, ~w(title body)a) |> validate_required([:title, :body])
    cs2 = cast(%Post{}, %{}, ~w(body title)a) |> validate_required([:body, :title])
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

  test "merge/2: fails when the :data, :repo or :action field are not equal" do
    cs1 = cast(%Post{title: "foo"}, %{}, ~w(title)a)
    cs2 = cast(%Post{title: "bar"}, %{}, ~w(title)a)

    assert_raise ArgumentError, "different :data when merging changesets", fn ->
      merge(cs1, cs2)
    end

    assert_raise ArgumentError, "different repos (`:foo` and `:bar`) when merging changesets", fn ->
      merge(%Ecto.Changeset{repo: :foo}, %Ecto.Changeset{repo: :bar})
    end

    assert_raise ArgumentError, "different actions (`:insert` and `:update`) when merging changesets", fn ->
      merge(%Ecto.Changeset{action: :insert}, %Ecto.Changeset{action: :update})
    end
  end

  test "change/2 with a struct" do
    changeset = change(%Post{})
    assert changeset.valid?
    assert changeset.data == %Post{}
    assert changeset.changes == %{}

    changeset = change(%Post{body: "bar"}, body: "bar")
    assert changeset.valid?
    assert changeset.data == %Post{body: "bar"}
    assert changeset.changes == %{}

    changeset = change(%Post{body: "bar"}, %{body: "bar", title: "foo"})
    assert changeset.valid?
    assert changeset.data == %Post{body: "bar"}
    assert changeset.changes == %{title: "foo"}

    changeset = change(%Post{}, body: "bar")
    assert changeset.valid?
    assert changeset.data == %Post{}
    assert changeset.changes == %{body: "bar"}

    changeset = change(%Post{}, %{body: "bar"})
    assert changeset.valid?
    assert changeset.data == %Post{}
    assert changeset.changes == %{body: "bar"}
  end

  test "change/2 with data and types" do
    datatypes = {%{title: "hello"}, %{title: :string}}
    changeset = change(datatypes)
    assert changeset.valid?
    assert changeset.data == %{title: "hello"}
    assert changeset.changes == %{}

    changeset = change(datatypes, title: "world")
    assert changeset.valid?
    assert changeset.data == %{title: "hello"}
    assert changeset.changes == %{title: "world"}
    assert apply_changes(changeset) == %{title: "world"}

    changeset = change(datatypes, title: "hello")
    assert changeset.valid?
    assert changeset.data == %{title: "hello"}
    assert changeset.changes == %{}
    assert apply_changes(changeset) == %{title: "hello"}
  end

  test "change/2 with a changeset" do
    base_changeset = cast(%Post{upvotes: 5}, %{title: "title"}, ~w(title)a)

    assert change(base_changeset) == base_changeset

    changeset = change(base_changeset, %{body: "body"})
    assert changeset.changes == %{title: "title", body: "body"}

    changeset = change(base_changeset, %{title: "new title"})
    assert changeset.changes == %{title: "new title"}

    changeset = change(base_changeset, title: "new title")
    assert changeset.changes == %{title: "new title"}

    changeset = change(base_changeset, body: nil)
    assert changeset.changes == %{title: "title"}

    changeset = change(base_changeset, %{upvotes: nil})
    assert changeset.changes == %{title: "title", upvotes: nil}

    changeset = change(base_changeset, %{upvotes: 5})
    assert changeset.changes == %{title: "title"}

    changeset = change(base_changeset, %{upvotes: 10})
    assert changeset.changes == %{title: "title", upvotes: 10}

    changeset = change(base_changeset, %{title: "new title", upvotes: 5})
    assert changeset.changes == %{title: "new title"}
  end

  test "change/2 semantic comparison" do
    post = %Post{decimal: Decimal.new("1.0")}
    changeset = change(post, decimal: Decimal.new(1))
    assert changeset.changes == %{}
  end

  test "change/2 with unknown field" do
    post = %Post{}

    assert_raise ArgumentError, ~r"unknown field `:unknown`", fn ->
      change(post, unknown: Decimal.new(1))
    end
  end

  test "change/2 with non-atom field" do
    post = %Post{}

    assert_raise ArgumentError, ~r"must be atoms, got: `\"bad\"`", fn ->
      change(post, %{"bad" => 42})
    end
  end

  test "fetch_field/2" do
    changeset = changeset(%Post{body: "bar"}, %{"title" => "foo"})

    assert fetch_field(changeset, :title) == {:changes, "foo"}
    assert fetch_field(changeset, :body) == {:data, "bar"}
    assert fetch_field(changeset, :other) == :error
  end

  test "fetch_field!/2" do
    changeset = changeset(%Post{body: "bar"}, %{"title" => "foo"})

    assert fetch_field!(changeset, :title) == "foo"
    assert fetch_field!(changeset, :body) == "bar"

    assert_raise KeyError, ~r/key :other not found in/, fn ->
      fetch_field!(changeset, :other)
    end
  end

  test "get_field/3" do
    changeset = changeset(%Post{body: "bar"}, %{"title" => "foo"})

    assert get_field(changeset, :title) == "foo"
    assert get_field(changeset, :body) == "bar"
    assert get_field(changeset, :body, "other") == "bar"
    assert get_field(changeset, :other) == nil
    assert get_field(changeset, :other, "other") == "other"
  end

  test "get_field/3 with associations" do
    post = %Post{comments: [%Comment{}]}
    changeset = change(post) |> put_assoc(:comments, [])

    assert get_field(changeset, :comments) == []
  end

  test "fetch_change/2" do
    changeset = changeset(%{"title" => "foo", "body" => nil, "upvotes" => nil})

    assert fetch_change(changeset, :title) == {:ok, "foo"}
    assert fetch_change(changeset, :body) == :error
    assert fetch_change(changeset, :upvotes) == {:ok, nil}
  end

  test "fetch_change!/2" do
    changeset = changeset(%{"title" => "foo", "body" => nil, "upvotes" => nil})

    assert fetch_change!(changeset, :title) == "foo"

    assert_raise KeyError, "key :body not found in: %{title: \"foo\", upvotes: nil}", fn ->
      fetch_change!(changeset, :body)
    end

    assert fetch_change!(changeset, :upvotes) == nil
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

    changeset =
      changeset(%Post{title: "mytitle"}, %{title: "MyTitle"})
      |> update_change(:title, &String.downcase/1)
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

    changeset = put_change(base_changeset, :body, nil)
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
    assert post.title == ""

    changeset = changeset(post, %{"title" => "foo"})
    changed_post = apply_changes(changeset)

    assert changed_post.__struct__ == post.__struct__
    assert changed_post.title == "foo"
  end

  describe "apply_action/2" do
    test "valid changeset" do
      post = %Post{}
      assert post.title == ""

      changeset = changeset(post, %{"title" => "foo"})
      assert changeset.valid?
      assert {:ok, changed_post} = apply_action(changeset, :update)

      assert changed_post.__struct__ == post.__struct__
      assert changed_post.title == "foo"
    end

    test "invalid changeset" do
      changeset =
        %Post{}
        |> changeset(%{"title" => "foo"})
        |> validate_length(:title, min: 10)

      refute changeset.valid?
      changeset_new_action = %Ecto.Changeset{changeset | action: :update}
      assert {:error, ^changeset_new_action} = apply_action(changeset, :update)
    end

    test "invalid action" do
      assert_raise ArgumentError, ~r/expected action to be an atom/, fn ->
        %Post{}
        |> changeset(%{})
        |> apply_action("invalid_action")
      end
    end
  end

  describe "apply_action!/2" do
    test "valid changeset" do
      changeset = changeset(%Post{}, %{"title" => "foo"})
      post = apply_action!(changeset, :update)
      assert post.title == "foo"
    end

    test "invalid changeset" do
      changeset =
        %Post{}
        |> changeset(%{"title" => "foo"})
        |> validate_length(:title, min: 10)

      assert_raise Ecto.InvalidChangesetError, fn ->
        apply_action!(changeset, :update)
      end
    end
  end

  ## Validations

  test "add_error/3" do
    changeset =
      changeset(%{})
      |> add_error(:foo, "bar")
    assert changeset.errors == [foo: {"bar", []}]

    changeset =
      changeset(%{})
      |> add_error(:foo, "bar", additional: "information")
    assert changeset.errors == [foo: {"bar", [additional: "information"]}]
  end

  test "validate_change/3" do
    # When valid
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_change(:title, fn :title, "hello" -> [] end)

    assert changeset.valid?
    assert changeset.errors == []

    # When invalid with binary
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_change(:title, fn :title, "hello" -> [title: "oops"] end)

    refute changeset.valid?
    assert changeset.errors == [title: {"oops", []}]

    # When invalid with tuple
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_change(:title, fn :title, "hello" -> [title: {"oops", type: "bar"}] end)

    refute changeset.valid?
    assert changeset.errors == [title: {"oops", type: "bar"}]

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

    # When virtual
    changeset =
      changeset(%{"virtual" => "hello"})
      |> validate_change(:virtual, fn :virtual, "hello" -> [] end)

    assert changeset.valid?
    assert changeset.errors == []

    # When unknown field
    assert_raise ArgumentError, ~r/unknown field :bad in/, fn  ->
      changeset(%{"title" => "hello"})
      |> validate_change(:bad, fn _, _ -> [] end)
    end
  end

  test "validate_change/4" do
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_change(:title, :oops, fn :title, "hello" -> [title: "oops"] end)

    refute changeset.valid?
    assert changeset.errors == [title: {"oops", []}]
    assert validations(changeset) == [title: :oops]

    changeset =
      changeset(%{})
      |> validate_change(:title, :oops, fn :title, "hello" -> [title: "oops"] end)

    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [title: :oops]
  end

  test "validate_required/2" do
    # When valid
    changeset =
      changeset(%{"title" => "hello", "body" => "something"})
      |> validate_required(:title)
    assert changeset.valid?
    assert changeset.errors == []

    # When missing
    changeset = changeset(%{}) |> validate_required(:title)
    refute changeset.valid?
    assert changeset.required == [:title]
    assert changeset.errors == [title: {"can't be blank", [validation: :required]}]

    # When nil
    changeset =
      changeset(%{title: nil, body: "\n"})
      |> validate_required([:title, :body], message: "is blank")
    refute changeset.valid?
    assert changeset.required == [:title, :body]
    assert changeset.changes == %{}
    assert changeset.errors == [title: {"is blank", [validation: :required]}, body: {"is blank", [validation: :required]}]

    # When :trim option is false
    changeset = changeset(%{title: " "}) |> validate_required(:title, trim: false)
    assert changeset.valid?
    assert changeset.errors == []

    changeset = changeset(%{color: <<12, 12, 12>>}) |> validate_required(:color, trim: false)
    assert changeset.valid?
    assert changeset.errors == []

    # When unknown field
    assert_raise ArgumentError, ~r/unknown field :bad in/, fn  ->
      changeset(%{"title" => "hello", "body" => "something"})
      |> validate_required(:bad)
    end

    # When field is not an atom
    assert_raise ArgumentError, ~r/expects field names to be atoms, got: `"title"`/, fn ->
      changeset(%{"title" => "hello"})
      |> validate_required("title")
    end

    # When field is nil
    assert_raise FunctionClauseError, fn ->
      changeset(%{"title" => "hello"})
      |> validate_required(nil)
    end
  end

  test "validate_format/3" do
    changeset =
      changeset(%{"title" => "foo@bar"})
      |> validate_format(:title, ~r/@/)
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [title: {:format, ~r/@/}]

    changeset =
      changeset(%{"title" => "foobar"})
      |> validate_format(:title, ~r/@/)
    refute changeset.valid?
    assert changeset.errors == [title: {"has invalid format", [validation: :format]}]
    assert validations(changeset) == [title: {:format, ~r/@/}]

    changeset =
      changeset(%{"title" => "foobar"})
      |> validate_format(:title, ~r/@/, message: "yada")
    assert changeset.errors == [title: {"yada", [validation: :format]}]
  end

  test "validate_inclusion/3" do
    changeset =
      changeset(%{"title" => "hello"})
      |> validate_inclusion(:title, ~w(hello))
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [title: {:inclusion, ~w(hello)}]

    changeset =
      changeset(%{"title" => "hello"})
      |> validate_inclusion(:title, ~w(world))
    refute changeset.valid?
    assert changeset.errors == [title: {"is invalid", [validation: :inclusion, enum: ~w(world)]}]
    assert validations(changeset) == [title: {:inclusion, ~w(world)}]

    changeset =
      changeset(%{"title" => "hello"})
      |> validate_inclusion(:title, ~w(world), message: "yada")
    assert changeset.errors == [title: {"yada", [validation: :inclusion, enum: ~w(world)]}]
  end

  test "validate_subset/3" do
    changeset =
      changeset(%{"topics" => ["cat", "dog"]})
      |> validate_subset(:topics, ~w(cat dog))
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [topics: {:subset, ~w(cat dog)}]

    changeset =
      changeset(%{"topics" => ["cat", "laptop"]})
      |> validate_subset(:topics, ~w(cat dog))
    refute changeset.valid?
    assert changeset.errors == [topics: {"has an invalid entry", [validation: :subset, enum: ~w(cat dog)]}]
    assert validations(changeset) == [topics: {:subset, ~w(cat dog)}]

    changeset =
      changeset(%{"topics" => ["laptop"]})
      |> validate_subset(:topics, ~w(cat dog), message: "yada")
    assert changeset.errors == [topics: {"yada", [validation: :subset, enum: ~w(cat dog)]}]
  end

  test "validate_exclusion/3" do
    changeset =
      changeset(%{"title" => "world"})
      |> validate_exclusion(:title, ~w(hello))
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [title: {:exclusion, ~w(hello)}]

    changeset =
      changeset(%{"title" => "world"})
      |> validate_exclusion(:title, ~w(world))
    refute changeset.valid?
    assert changeset.errors == [title: {"is reserved", [validation: :exclusion, enum: ~w(world)]}]
    assert validations(changeset) == [title: {:exclusion, ~w(world)}]

    changeset =
      changeset(%{"title" => "world"})
      |> validate_exclusion(:title, ~w(world), message: "yada")
    assert changeset.errors == [title: {"yada", [validation: :exclusion, enum: ~w(world)]}]
  end

  test "validate_length/3 with string" do
    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, min: 3, max: 7)
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [title: {:length, [min: 3, max: 7]}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, min: 5, max: 5)
    assert changeset.valid?

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, is: 5)
    assert changeset.valid?

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, min: 6)
    refute changeset.valid?
    assert changeset.errors == [title: {"should be at least %{count} character(s)", count: 6, validation: :length, kind: :min, type: :string}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, max: 4)
    refute changeset.valid?
    assert changeset.errors == [title: {"should be at most %{count} character(s)", count: 4, validation: :length, kind: :max, type: :string}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, is: 10)
    refute changeset.valid?
    assert changeset.errors == [title: {"should be %{count} character(s)", count: 10, validation: :length, kind: :is, type: :string}]

    changeset = changeset(%{"title" => "world"}) |> validate_length(:title, is: 10, message: "yada")
    assert changeset.errors == [title: {"yada", count: 10, validation: :length, kind: :is, type: :string}]

    changeset = changeset(%{"title" => "\u0065\u0301"}) |> validate_length(:title, max: 1)
    assert changeset.valid?

    changeset = changeset(%{"title" => "\u0065\u0301"}) |> validate_length(:title, max: 1, count: :codepoints)
    refute changeset.valid?
    assert changeset.errors == [title: {"should be at most %{count} character(s)", count: 1, validation: :length, kind: :max, type: :string}]
  end

  test "validate_length/3 with binary" do
    changeset =
      changeset(%{"body" => <<0, 1, 2, 3>>})
      |> validate_length(:body, count: :bytes, min: 3, max: 7)

    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [body: {:length, [count: :bytes, min: 3, max: 7]}]

    changeset =
      changeset(%{"body" => <<0, 1, 2, 3, 4>>})
      |> validate_length(:body, count: :bytes, min: 5, max: 5)

    assert changeset.valid?

    changeset =
      changeset(%{"body" => <<0, 1, 2, 3, 4>>}) |> validate_length(:body, count: :bytes, is: 5)

    assert changeset.valid?

    changeset =
      changeset(%{"body" => <<0, 1, 2, 3, 4>>}) |> validate_length(:body, count: :bytes, min: 6)

    refute changeset.valid?

    assert changeset.errors == [
             body:
               {"should be at least %{count} byte(s)", count: 6, validation: :length, kind: :min, type: :binary}
           ]

    changeset =
      changeset(%{"body" => <<0, 1, 2, 3, 4>>}) |> validate_length(:body, count: :bytes, max: 4)

    refute changeset.valid?

    assert changeset.errors == [
             body: {"should be at most %{count} byte(s)", count: 4, validation: :length, kind: :max, type: :binary}
           ]

    changeset =
      changeset(%{"body" => <<0, 1, 2, 3, 4>>}) |> validate_length(:body, count: :bytes, is: 10)

    refute changeset.valid?

    assert changeset.errors == [
             body: {"should be %{count} byte(s)", count: 10, validation: :length, kind: :is, type: :binary}
           ]

    changeset =
      changeset(%{"body" => <<0, 1, 2, 3, 4>>})
      |> validate_length(:body, count: :bytes, is: 10, message: "yada")

    assert changeset.errors == [body: {"yada", count: 10, validation: :length, kind: :is, type: :binary}]
  end

  test "validate_length/3 with list" do
    changeset = changeset(%{"topics" => ["Politics", "Security", "Economy", "Elections"]}) |> validate_length(:topics, min: 3, max: 7)
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [topics: {:length, [min: 3, max: 7]}]

    changeset = changeset(%{"topics" => ["Politics", "Security"]}) |> validate_length(:topics, min: 2, max: 2)
    assert changeset.valid?

    changeset = changeset(%{"topics" => ["Politics", "Security", "Economy"]}) |> validate_length(:topics, is: 3)
    assert changeset.valid?

    changeset = changeset(%{"topics" => ["Politics", "Security"]}) |> validate_length(:topics, min: 6, foo: true)
    refute changeset.valid?
    assert changeset.errors == [topics: {"should have at least %{count} item(s)", count: 6, validation: :length, kind: :min, type: :list}]

    changeset = changeset(%{"topics" => ["Politics", "Security", "Economy"]}) |> validate_length(:topics, max: 2)
    refute changeset.valid?
    assert changeset.errors == [topics: {"should have at most %{count} item(s)", count: 2, validation: :length, kind: :max, type: :list}]

    changeset = changeset(%{"topics" => ["Politics", "Security"]}) |> validate_length(:topics, is: 10)
    refute changeset.valid?
    assert changeset.errors == [topics: {"should have %{count} item(s)", count: 10, validation: :length, kind: :is, type: :list}]

    changeset = changeset(%{"topics" => ["Politics", "Security"]}) |> validate_length(:topics, is: 10, message: "yada")
    assert changeset.errors == [topics: {"yada", count: 10, validation: :length, kind: :is, type: :list}]
  end

  test "validate_length/3 with associations" do
    post = %Post{comments: [%Comment{id: 1}]}
    changeset = change(post) |> put_assoc(:comments, []) |> validate_length(:comments, min: 1)
    assert changeset.errors == [comments: {"should have at least %{count} item(s)", count: 1, validation: :length, kind: :min, type: :list}]

    changeset = change(post) |> put_assoc(:comments, [%Comment{id: 2}, %Comment{id: 3}]) |> validate_length(:comments, max: 2)
    assert changeset.valid?
  end

  test "validate_number/3" do
    changeset = changeset(%{"upvotes" => 3})
                |> validate_number(:upvotes, greater_than: 0)
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [upvotes: {:number, [greater_than: 0]}]

    # Single error
    changeset = changeset(%{"upvotes" => -1})
                |> validate_number(:upvotes, greater_than: 0)
    refute changeset.valid?
    assert changeset.errors == [upvotes: {"must be greater than %{number}", validation: :number, kind: :greater_than, number: 0}]
    assert validations(changeset) == [upvotes: {:number, [greater_than: 0]}]

    # Non equality error
    changeset = changeset(%{"upvotes" => 1})
                |> validate_number(:upvotes, not_equal_to: 1)
    refute changeset.valid?
    assert changeset.errors == [upvotes: {"must be not equal to %{number}", validation: :number, kind: :not_equal_to, number: 1}]
    assert validations(changeset) == [upvotes: {:number, [not_equal_to: 1]}]

    # Multiple validations
    changeset = changeset(%{"upvotes" => 3})
                |> validate_number(:upvotes, greater_than: 0, less_than: 100)
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [upvotes: {:number, [greater_than: 0, less_than: 100]}]

    # Multiple validations with multiple errors
    changeset = changeset(%{"upvotes" => 3})
                |> validate_number(:upvotes, greater_than: 100, less_than: 0)
    refute changeset.valid?
    assert changeset.errors == [upvotes: {"must be greater than %{number}", validation: :number, kind: :greater_than, number: 100}]

    # Multiple validations with custom message errors
    changeset = changeset(%{"upvotes" => 3})
                |> validate_number(:upvotes, greater_than: 100, less_than: 0, message: "yada")
    assert changeset.errors == [upvotes: {"yada", validation: :number, kind: :greater_than, number: 100}]
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

    changeset = changeset(%{"decimal" => Decimal.new(0)})
                |> validate_number(:decimal, not_equal_to: Decimal.new(-1))
    assert changeset.valid?

    changeset = changeset(%{"decimal" => Decimal.new(-3)})
                |> validate_number(:decimal, less_than_or_equal_to: Decimal.new(-1))
    assert changeset.valid?
    changeset = changeset(%{"decimal" => Decimal.new(-3)})
                |> validate_number(:decimal, less_than_or_equal_to: Decimal.new(-3))
    assert changeset.valid?

    changeset = changeset(%{"decimal" => Decimal.new(-1)})
                |> validate_number(:decimal, greater_than_or_equal_to: Decimal.new("-1.5"))
    assert changeset.valid?
    changeset = changeset(%{"decimal" => Decimal.new("1.5")})
                |> validate_number(:decimal, greater_than_or_equal_to: Decimal.new("1.5"))
    assert changeset.valid?

    changeset = changeset(%{"decimal" => Decimal.new("4.9")})
                |> validate_number(:decimal, greater_than_or_equal_to: 4.9)
    assert changeset.valid?
    changeset = changeset(%{"decimal" => Decimal.new(5)})
                |> validate_number(:decimal, less_than: 4)
    refute changeset.valid?
  end

  test "validate_number/3 with bad options" do
    assert_raise ArgumentError, ~r"unknown option :min given to validate_number/3", fn  ->
      validate_number(changeset(%{"upvotes" => 1}), :upvotes, min: Decimal.new("1.5"))
    end
  end

  test "validate_confirmation/3" do
    changeset = changeset(%{"title" => "title", "title_confirmation" => "title"})
                |> validate_confirmation(:title)
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [{:title, {:confirmation, []}}]

    changeset = changeset(%{"title" => "title"})
                |> validate_confirmation(:title)
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [{:title, {:confirmation, []}}]

    changeset = changeset(%{"title" => "title"})
                |> validate_confirmation(:title, required: false)
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [{:title, {:confirmation, [required: false]}}]

    changeset = changeset(%{"title" => "title"})
                |> validate_confirmation(:title, required: true)
    refute changeset.valid?
    assert changeset.errors == [title_confirmation: {"can't be blank", [validation: :required]}]
    assert validations(changeset) == [{:title, {:confirmation, [required: true]}}]

    changeset = changeset(%{"title" => "title", "title_confirmation" => nil})
                |> validate_confirmation(:title)
    refute changeset.valid?
    assert changeset.errors == [title_confirmation: {"does not match confirmation", [validation: :confirmation]}]
    assert validations(changeset) == [{:title, {:confirmation, []}}]

    changeset = changeset(%{"title" => "title", "title_confirmation" => "not title"})
                |> validate_confirmation(:title)
    refute changeset.valid?
    assert changeset.errors == [title_confirmation: {"does not match confirmation", [validation: :confirmation]}]
    assert validations(changeset) == [{:title, {:confirmation, []}}]

    changeset = changeset(%{"title" => "title", "title_confirmation" => "not title"})
                |> validate_confirmation(:title, message: "doesn't match field below")
    refute changeset.valid?
    assert changeset.errors == [title_confirmation: {"doesn't match field below", [validation: :confirmation]}]
    assert validations(changeset) == [{:title, {:confirmation, [message: "doesn't match field below"]}}]

    # Skip when no parameter
    changeset = changeset(%{"title" => "title"})
                |> validate_confirmation(:title, message: "password doesn't match")
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [{:title, {:confirmation, [message: "password doesn't match"]}}]

    # With casting
    changeset = changeset(%{"upvotes" => "1", "upvotes_confirmation" => "1"})
                |> validate_confirmation(:upvotes)
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [{:upvotes, {:confirmation, []}}]

    # With blank change
    changeset = changeset(%{"password" => "", "password_confirmation" => "password"})
                |> validate_confirmation(:password)
    refute changeset.valid?
    assert changeset.errors == [password_confirmation: {"does not match confirmation", [validation: :confirmation]}]

    # With missing change
    changeset = changeset(%{"password_confirmation" => "password"})
                |> validate_confirmation(:password)
    refute changeset.valid?
    assert changeset.errors == [password_confirmation: {"does not match confirmation", [validation: :confirmation]}]

    # invalid params
    changeset = changeset(:invalid)
                |> validate_confirmation(:password)
    refute changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == []
  end

  test "validate_acceptance/3" do
    # accepted
    changeset = changeset(%{"terms_of_service" => "true"})
                |> validate_acceptance(:terms_of_service)
    assert changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [terms_of_service: {:acceptance, []}]

    # not accepted
    changeset = changeset(%{"terms_of_service" => "false"})
                |> validate_acceptance(:terms_of_service)
    refute changeset.valid?
    assert changeset.errors == [terms_of_service: {"must be accepted", [validation: :acceptance]}]
    assert validations(changeset) == [terms_of_service: {:acceptance, []}]

    changeset = changeset(%{"terms_of_service" => "other"})
                |> validate_acceptance(:terms_of_service)
    refute changeset.valid?
    assert changeset.errors == [terms_of_service: {"must be accepted", [validation: :acceptance]}]
    assert validations(changeset) == [terms_of_service: {:acceptance, []}]

    # empty params
    changeset = changeset(%{})
                |> validate_acceptance(:terms_of_service)
    refute changeset.valid?
    assert changeset.errors == [terms_of_service: {"must be accepted", [validation: :acceptance]}]
    assert validations(changeset) == [terms_of_service: {:acceptance, []}]

    # invalid params
    changeset = changeset(:invalid)
                |> validate_acceptance(:terms_of_service)
    refute changeset.valid?
    assert changeset.errors == []
    assert validations(changeset) == [terms_of_service: {:acceptance, []}]

    # custom message
    changeset = changeset(%{})
                |> validate_acceptance(:terms_of_service, message: "must be abided")
    refute changeset.valid?
    assert changeset.errors == [terms_of_service: {"must be abided", [validation: :acceptance]}]
    assert validations(changeset) == [terms_of_service: {:acceptance, [message: "must be abided"]}]
  end

  alias Ecto.TestRepo

  describe "unsafe_validate_unique/3" do
    setup do
      dup_result = {1, [true]}
      no_dup_result = {0, []}
      base_changeset = changeset(%Post{}, %{"title" => "Hello World", "body" => "hi"})
      [dup_result: dup_result, no_dup_result: no_dup_result, base_changeset: base_changeset]
    end

    defmodule MockRepo do
      @moduledoc """
      Allows tests to verify or refute that a query was run.
      """

      def one(query, opts \\ []) do
        send(self(), [__MODULE__, function: :one, query: query, opts: opts])
      end
    end

    test "validates the uniqueness of a single field", context do
      Process.put(:test_repo_all_results, context.dup_result)
      changeset = unsafe_validate_unique(context.base_changeset, :title, TestRepo)

      assert changeset.errors ==
               [title: {"has already been taken", validation: :unsafe_unique, fields: [:title]}]

      Process.put(:test_repo_all_results, context.no_dup_result)
      changeset = unsafe_validate_unique(context.base_changeset, :title, TestRepo)
      assert changeset.valid?
    end

    test "validates the uniqueness of a combination of fields", context do
      Process.put(:test_repo_all_results, context.dup_result)
      changeset = unsafe_validate_unique(context.base_changeset, [:title, :body], TestRepo)

      assert changeset.errors ==
               [
                 title:
                   {"has already been taken", validation: :unsafe_unique, fields: [:title, :body]}
               ]

      Process.put(:test_repo_all_results, context.no_dup_result)
      changeset = unsafe_validate_unique(context.base_changeset, [:title, :body], TestRepo)
      assert changeset.valid?
    end

    test "allows setting a custom error message", context do
      Process.put(:test_repo_all_results, context.dup_result)

      changeset =
        unsafe_validate_unique(context.base_changeset, [:title], TestRepo, message: "is taken")

      assert changeset.errors ==
               [title: {"is taken", validation: :unsafe_unique, fields: [:title]}]
    end

    test "accepts a prefix option", context do
      Process.put(:test_repo_all_results, context.dup_result)

      changeset =
        unsafe_validate_unique(context.base_changeset, :title, TestRepo, prefix: "public")

      assert changeset.errors ==
               [title: {"has already been taken", validation: :unsafe_unique, fields: [:title]}]

      Process.put(:test_repo_all_results, context.no_dup_result)

      changeset =
        unsafe_validate_unique(context.base_changeset, :title, TestRepo, prefix: "public")

      assert changeset.valid?
    end

    test "only queries the db when necessary" do
      body_change = changeset(%Post{title: "Hello World", body: "hi"}, %{body: "ho"})
      unsafe_validate_unique(body_change, :body, MockRepo)
      assert_receive [MockRepo, function: :one, query: %Ecto.Query{}, opts: []]

      unsafe_validate_unique(body_change, [:body, :title], MockRepo)
      assert_receive [MockRepo, function: :one, query: %Ecto.Query{}, opts: []]

      unsafe_validate_unique(body_change, :title, MockRepo)
      # no overlap between changed fields and those required to be unique
      refute_receive [MockRepo, function: :one, query: %Ecto.Query{}, opts: []]
    end
  end

  ## Locks

  test "optimistic_lock/3 with changeset with default incremeter" do
    changeset = changeset(%{}) |> optimistic_lock(:upvotes)
    assert changeset.filters == %{upvotes: 0}
    assert changeset.repo_changes == %{upvotes: 1}

    changeset = changeset(%Post{upvotes: 2}, %{upvotes: 1}) |> optimistic_lock(:upvotes)
    assert changeset.filters == %{upvotes: 1}
    assert changeset.repo_changes == %{upvotes: 2}

    # Assert default increment will rollover to 1 when the current one is equal or graeter than 2_147_483_647
    changeset = changeset(%Post{upvotes: 2_147_483_647}, %{}) |> optimistic_lock(:upvotes)
    assert changeset.filters == %{upvotes: 2_147_483_647}
    assert changeset.repo_changes == %{upvotes: 1}

    changeset = changeset(%Post{upvotes: 3_147_483_647}, %{}) |> optimistic_lock(:upvotes)
    assert changeset.filters == %{upvotes: 3_147_483_647}
    assert changeset.repo_changes == %{upvotes: 1}

    changeset = changeset(%Post{upvotes: 2_147_483_647}, %{upvotes: 2_147_483_648}) |> optimistic_lock(:upvotes)
    assert changeset.filters == %{upvotes: 2_147_483_648}
    assert changeset.repo_changes == %{upvotes: 1}
 end

  test "optimistic_lock/3 with struct" do
    changeset = %Post{} |> optimistic_lock(:upvotes)
    assert changeset.filters == %{upvotes: 0}
    assert changeset.repo_changes == %{upvotes: 1}
  end

  test "optimistic_lock/3 with custom incrementer" do
    changeset = %Post{} |> optimistic_lock(:upvotes, &(&1 - 1))
    assert changeset.filters == %{upvotes: 0}
    assert changeset.repo_changes == %{upvotes: -1}
  end

  ## Constraints
  test "check_constraint/3" do
    changeset = change(%Post{}) |> check_constraint(:title, name: :title_must_be_short)
    assert constraints(changeset) ==
           [%{type: :check, field: :title, constraint: "title_must_be_short", match: :exact,
              error_message: "is invalid", error_type: :check}]

    changeset = change(%Post{}) |> check_constraint(:title, name: :title_must_be_short, message: "cannot be more than 15 characters")
    assert constraints(changeset) ==
           [%{type: :check, field: :title, constraint: "title_must_be_short", match: :exact,
              error_message: "cannot be more than 15 characters", error_type: :check}]

    assert_raise ArgumentError, ~r/invalid match type: :invalid/, fn ->
      change(%Post{}) |> check_constraint(:title, name: :whatever, match: :invalid, message: "match is invalid")
    end

    assert_raise ArgumentError, ~r/supply the name/, fn ->
      check_constraint(:title, message: "cannot be more than 15 characters")
    end
  end

  test "unique_constraint/3" do
    changeset = change(%Post{}) |> unique_constraint(:title)

    assert constraints(changeset) ==
           [%{type: :unique, field: :title, constraint: "posts_title_index", match: :exact,
              error_message: "has already been taken", error_type: :unique}]

    changeset = change(%Post{}) |> unique_constraint(:title, name: :whatever, message: "is taken")
    assert constraints(changeset) ==
           [%{type: :unique, field: :title, constraint: "whatever", match: :exact, error_message: "is taken", error_type: :unique}]

    changeset = change(%Post{}) |> unique_constraint(:title, name: :whatever, match: :suffix, message: "is taken")
    assert constraints(changeset) ==
           [%{type: :unique, field: :title, constraint: "whatever", match: :suffix, error_message: "is taken", error_type: :unique}]

    changeset = change(%Post{}) |> unique_constraint(:title, name: :whatever, match: :prefix, message: "is taken")
    assert constraints(changeset) ==
           [%{type: :unique, field: :title, constraint: "whatever", match: :prefix, error_message: "is taken", error_type: :unique}]

    assert_raise ArgumentError, ~r/invalid match type: :invalid/, fn ->
      change(%Post{}) |> unique_constraint(:title, name: :whatever, match: :invalid, message: "is taken")
    end
  end

  test "unique_constraint/3 on field with :source" do
    changeset = change(%Post{}) |> unique_constraint(:permalink)

    assert constraints(changeset) ==
           [%{type: :unique, field: :permalink, constraint: "posts_url_index", match: :exact,
              error_message: "has already been taken", error_type: :unique}]

    changeset = change(%Post{}) |> unique_constraint(:permalink, name: :whatever, message: "is taken")
    assert constraints(changeset) ==
           [%{type: :unique, field: :permalink, constraint: "whatever", match: :exact, error_message: "is taken", error_type: :unique}]

    changeset = change(%Post{}) |> unique_constraint(:permalink, name: :whatever, match: :suffix, message: "is taken")
    assert constraints(changeset) ==
           [%{type: :unique, field: :permalink, constraint: "whatever", match: :suffix, error_message: "is taken", error_type: :unique}]

    assert_raise ArgumentError, ~r/invalid match type: :invalid/, fn ->
      change(%Post{}) |> unique_constraint(:permalink, name: :whatever, match: :invalid, message: "is taken")
    end
  end

  test "unique_constraint/3 with multiple fields" do
    changeset = change(%Post{}) |> unique_constraint([:permalink, :color])

    assert constraints(changeset) ==
           [%{type: :unique, field: :permalink, constraint: "posts_url_color_index", match: :exact,
              error_message: "has already been taken", error_type: :unique}]
  end

  test "foreign_key_constraint/3" do
    changeset = change(%Comment{}) |> foreign_key_constraint(:post_id)
    assert constraints(changeset) ==
           [%{type: :foreign_key, field: :post_id, constraint: "comments_post_id_fkey", match: :exact,
              error_message: "does not exist", error_type: :foreign}]

    changeset = change(%Comment{}) |> foreign_key_constraint(:post_id, name: :whatever, message: "is not available")
    assert constraints(changeset) ==
           [%{type: :foreign_key, field: :post_id, constraint: "whatever", match: :exact, error_message: "is not available", error_type: :foreign}]
  end

  test "foreign_key_constraint/3 on field with :source" do
    changeset = change(%Post{}) |> foreign_key_constraint(:permalink)
    assert constraints(changeset) ==
           [%{type: :foreign_key, field: :permalink, constraint: "posts_url_fkey", match: :exact,
              error_message: "does not exist", error_type: :foreign}]

    changeset = change(%Post{}) |> foreign_key_constraint(:permalink, name: :whatever, message: "is not available")
    assert constraints(changeset) ==
           [%{type: :foreign_key, field: :permalink, constraint: "whatever", match: :exact, error_message: "is not available", error_type: :foreign}]
  end

  test "assoc_constraint/3" do
    changeset = change(%Comment{}) |> assoc_constraint(:post)
    assert constraints(changeset) ==
           [%{type: :foreign_key, field: :post, constraint: "comments_post_id_fkey", match: :exact,
              error_message: "does not exist", error_type: :assoc}]

    changeset = change(%Comment{}) |> assoc_constraint(:post, name: :whatever, message: "is not available")
    assert constraints(changeset) ==
           [%{type: :foreign_key, field: :post, constraint: "whatever", match: :exact, error_message: "is not available", error_type: :assoc}]
  end

  test "assoc_constraint/3 on field with :source" do
    changeset = change(%Post{}) |> assoc_constraint(:category)
    assert constraints(changeset) ==
           [%{type: :foreign_key, field: :category, constraint: "posts_category_id_fkey", match: :exact,
              error_message: "does not exist", error_type: :assoc}]

    changeset = change(%Post{}) |> assoc_constraint(:category, name: :whatever, message: "is not available")
    assert constraints(changeset) ==
           [%{type: :foreign_key, field: :category, constraint: "whatever", match: :exact, error_message: "is not available", error_type: :assoc}]
  end

  test "assoc_constraint/3 with errors" do
    message = ~r"cannot add constraint to changeset because association `unknown` does not exist. Did you mean one of `category`, `comment`, `comments`?"
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
    assert constraints(changeset) ==
           [%{type: :foreign_key, field: :comments, constraint: "comments_post_id_fkey", match: :exact,
              error_message: "are still associated with this entry", error_type: :no_assoc}]

    changeset = change(%Post{}) |> no_assoc_constraint(:comments, name: :whatever, message: "exists")
    assert constraints(changeset) ==
           [%{type: :foreign_key, field: :comments, constraint: "whatever", match: :exact,
              error_message: "exists", error_type: :no_assoc}]
  end

  test "no_assoc_constraint/3 with has_one" do
    changeset = change(%Post{}) |> no_assoc_constraint(:comment)
    assert constraints(changeset) ==
           [%{type: :foreign_key, field: :comment, constraint: "comments_post_id_fkey", match: :exact,
              error_message: "is still associated with this entry", error_type: :no_assoc}]

    changeset = change(%Post{}) |> no_assoc_constraint(:comment, name: :whatever, message: "exists")
    assert constraints(changeset) ==
           [%{type: :foreign_key, field: :comment, constraint: "whatever", match: :exact,
              error_message: "exists", error_type: :no_assoc}]
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

  test "exclusion_constraint/3" do
    changeset = change(%Post{}) |> exclusion_constraint(:title)
    assert constraints(changeset) ==
           [%{type: :exclusion, field: :title, constraint: "posts_title_exclusion", match: :exact,
              error_message: "violates an exclusion constraint", error_type: :exclusion}]

    changeset = change(%Post{}) |> exclusion_constraint(:title, name: :whatever, message: "is invalid")
    assert constraints(changeset) ==
           [%{type: :exclusion, field: :title, constraint: "whatever", match: :exact,
              error_message: "is invalid", error_type: :exclusion}]

    assert_raise ArgumentError, ~r/invalid match type: :invalid/, fn ->
      change(%Post{}) |> exclusion_constraint(:title, name: :whatever, match: :invalid, message: "match is invalid")
    end
  end

  ## traverse_errors

  test "traverses changeset errors" do
    changeset =
      changeset(%{"title" => "title", "body" => "hi", "upvotes" => :bad})
      |> validate_length(:body, min: 3)
      |> validate_format(:body, ~r/888/)
      |> add_error(:title, "is taken", name: "your title")

    errors = traverse_errors(changeset, fn
      {"is invalid", [type: type, validation: :cast]} ->
        "expected to be #{inspect(type)}"
      {"is taken", keys} ->
        String.upcase("#{keys[:name]} is taken")
      {msg, keys} ->
        msg
        |> String.replace("%{count}", to_string(keys[:count]))
        |> String.upcase()
    end)

    assert errors == %{
      body: ["HAS INVALID FORMAT", "SHOULD BE AT LEAST 3 CHARACTER(S)"],
      title: ["YOUR TITLE IS TAKEN"],
      upvotes: ["expected to be :integer"],
    }
  end

  test "traverses changeset errors with field" do
    changeset =
      changeset(%{"title" => "title", "body" => "hi", "upvotes" => :bad})
      |> validate_length(:body, min: 3)
      |> validate_format(:body, ~r/888/)
      |> validate_inclusion(:body, ["hola", "bonjour", "hallo"])
      |> add_error(:title, "is taken", name: "your title")

    errors = traverse_errors(changeset, fn
      %Ecto.Changeset{}, field, {_, [type: type, validation: :cast]} ->
        "expected #{field} to be #{inspect(type)}"
      %Ecto.Changeset{}, field, {_, [name: "your title"]} ->
        "value in #{field} is taken"
        |> String.upcase()
      %Ecto.Changeset{}, field, {_, [count: 3, validation: :length, kind: :min, type: :string] = keys} ->
        "should be at least #{keys[:count]} character(s) in field #{field}"
        |> String.upcase()
      %Ecto.Changeset{validations: validations}, field, {_, [validation: :format]} ->
        validation = Keyword.get_values(validations, field)
        "field #{field} should match format #{inspect validation[:format]}"
      %Ecto.Changeset{validations: validations}, field, {_, [validation: :inclusion, enum: _]} ->
        validation = Keyword.get_values(validations, field)
        values = Enum.join(validation[:inclusion], ", ")
        "#{field} value should be in #{values}"
    end)

    assert errors == %{
      body: ["body value should be in hola, bonjour, hallo",
             "field body should match format ~r/888/",
             "SHOULD BE AT LEAST 3 CHARACTER(S) IN FIELD BODY"],
      title: ["VALUE IN TITLE IS TAKEN"],
      upvotes: ["expected upvotes to be :integer"],
    }
  end

  ## inspect

  test "inspects relevant data" do
    assert inspect(%Ecto.Changeset{}) ==
           "#Ecto.Changeset<action: nil, changes: %{}, errors: [], data: nil, valid?: false>"

    assert inspect(changeset(%{"title" => "title", "body" => "hi"})) ==
           "#Ecto.Changeset<action: nil, changes: %{body: \"hi\", title: \"title\"}, " <>
           "errors: [], data: #Ecto.ChangesetTest.Post<>, valid?: true>"
  end
end
