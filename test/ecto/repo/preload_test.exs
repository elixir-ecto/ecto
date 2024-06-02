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
      |> validate_required([:name])
      |> validate_length(:name, max: 20)
      |> cast_assoc(:books, sort_param: :books_sort)
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
      |> validate_required([:title])
      |> cast_assoc(:collection)
      |> cast_assoc(:chapters, sort_param: :chapters_sort)
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
      |> validate_required([:title])
      |> cast_assoc(:book)
    end
  end

  @collection_attrs %{
    "name" => "The Con Collection",
    "books_sort" => [0, "new"],
    "books" => %{
      0 => %{
        "title" => "Necronomicon",
        "chapters" => [
          %{"title" => "Necro 1"},
        ]
      }
    }
  }

  test "preload_in_changeset" do
    changeset =
      %Collection{}
      |> TestRepo.preload(books: [:chapters])
      |> Collection.changeset(@collection_attrs)

    # There are now two book changesets
    assert [book_changeset_1, book_changeset_2] = changeset.changes.books

    assert %Ecto.Changeset{} = book_changeset_1
    assert %Ecto.Changeset{} = book_changeset_2

    # The associations are not loaded!
    assert %Ecto.Association.NotLoaded{} = book_changeset_1.data.chapters
    assert %Ecto.Association.NotLoaded{} = book_changeset_2.data.chapters

    # Call our new `preload_in_changeset/2` function
    preloaded_changeset = TestRepo.preload_in_changeset(changeset, books: [:chapters])

    assert [preloaded_book_changeset_1, preloaded_book_changeset_2] = preloaded_changeset.changes.books

    assert %Ecto.Changeset{} = preloaded_book_changeset_1
    assert %Ecto.Changeset{} = preloaded_book_changeset_2

    # Preloaded (empty) associations
    assert [] == preloaded_book_changeset_1.data.chapters
    assert [] == preloaded_book_changeset_2.data.chapters
  end
end
