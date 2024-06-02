defmodule Ecto.Repo.PreloadTest do
  use ExUnit.Case, async: true
  require Ecto.TestRepo, as: TestRepo

  defmodule Collection do
    use Ecto.Schema
    import Ecto.Changeset

    alias Ecto.Repo.PreloadTest.Book

    schema "collections" do
      field :name
      has_many :books, Book
    end

    def changeset(%__MODULE__{} = collection, attrs) do
      collection
      |> cast(attrs, [:name])
      |> validate_length(:name, max: 20)
      |> cast_assoc(:books)
    end
  end

  defmodule Book do
    use Ecto.Schema
    import Ecto.Changeset

    alias Ecto.Repo.PreloadTest.{Collection, Chapter}

    schema "books" do
      field :title
      belongs_to :collection, Collection
      has_many :chapters, Chapter
    end

    def changeset(%__MODULE__{} = book, attrs) do
      book
      |> cast(attrs, [:title, :collection_id])
      |> cast_assoc(:collection)
      |> cast_assoc(:chapters)
    end
  end

  defmodule Chapter do
    use Ecto.Schema
    import Ecto.Changeset

    alias Ecto.Repo.PreloadTest.Book

    schema "chapters" do
      field :title
      belongs_to :book, Book
    end

    def changeset(%__MODULE__{} = chapter, attrs) do
      chapter
      |> cast(attrs, [:title, :book_id])
      |> cast_assoc(:book)
    end
  end

  @collection_attrs %{
    "name" => "The Con Collection",
    "books" => [
      %{
        "title" => "Necronomicon",
        "chapters" => [
          %{"title" => "Necro 1"},
        ]
      }
    ]
  }

  @tag skip: true
  test "preload_in_result - {:ok, struct}" do
    # Insert a new collection
    {:ok, inserted_collection} =
      %Collection{}
      |> Collection.changeset(@collection_attrs)
      |> TestRepo.insert()

    # Get the associations (which are not preloaded by default!)
    retreived_collection = TestRepo.get!(Collection, inserted_collection.id)

    {:ok, _updated_collection} =
      retreived_collection
      |> Collection.changeset(%{"name" => "A valid name"})
      |> TestRepo.update()
      |> TestRepo.preload_in_result(books: [:chapters])
  end
end
