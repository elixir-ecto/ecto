defmodule Ecto.Integration.Schema do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      type =
        Application.get_env(:ecto, :primary_key_type) ||
        raise ":primary_key_type not set in :ecto application"
      @primary_key {:id, type, autogenerate: true}
      @foreign_key_type type
    end
  end
end

defmodule Ecto.Integration.Post do
  @moduledoc """
  This module is used to test:

    * Overall functionality
    * Overall types
    * Non-null timestamps
    * Relationships
    * Dependent callbacks

  """
  use Ecto.Integration.Schema
  import Ecto.Changeset

  schema Ecto.Integration, "posts" do
    field :counter, :id # Same as integer
    field :title, :string
    field :text, :binary
    field :temp, :string, default: "temp", virtual: true
    field :public, :boolean, default: true
    field :cost, :decimal
    field :visits, :integer
    field :intensity, :float
    field :bid, :binary_id
    field :uuid, Ecto.UUID, autogenerate: true
    field :meta, :map
    field :links, {:map, :string}
    field :posted, Ecto.Date
    has_many :comments, Comment, on_delete: :delete_all, on_replace: :delete
    has_one :permalink, Permalink, on_delete: :delete_all, on_replace: :delete
    has_many :comments_authors, through: [:comments, :author]
    belongs_to :author, User
    many_to_many :users, User,
      join_through: "posts_users", on_delete: :delete_all, on_replace: :delete
    many_to_many :customs, Custom,
      join_through: "posts_customs", join_keys: [post_id: :uuid, custom_id: :bid],
      on_delete: :delete_all, on_replace: :delete
    many_to_many :unique_users, User,
      join_through: PostUserCompositePk
    has_many :users_comments, through: [:users, :comments]
    has_many :comments_authors_permalinks, through: [:comments_authors, :permalink]
    timestamps()
    has_one :post_user_composite_pk, PostUserCompositePk
  end

  def changeset(schema, params) do
    cast(schema, params, ~w(counter title text temp public cost visits
                           intensity bid uuid meta posted))
  end
end

defmodule Ecto.Integration.PostUsecTimestamps do
  @moduledoc """
  This module is used to test:

    * Usec timestamps

  """
  use Ecto.Integration.Schema

  schema "posts" do
    field :title, :string
    timestamps usec: true
  end
end

defmodule Ecto.Integration.Comment do
  @moduledoc """
  This module is used to test:

    * Optimistic lock
    * Relationships
    * Dependent callbacks

  """
  use Ecto.Integration.Schema

  schema Ecto.Integration, "comments" do
    field :text, :string
    field :lock_version, :integer, default: 1
    belongs_to :post, Post
    belongs_to :author, User
    has_one :post_permalink, through: [:post, :permalink]
  end
end

defmodule Ecto.Integration.Permalink do
  @moduledoc """
  This module is used to test:

    * Relationships
    * Dependent callbacks

  """
  use Ecto.Integration.Schema

  schema Ecto.Integration, "permalinks" do
    field :url, :string
    belongs_to :post, Post, on_replace: :nilify
    belongs_to :user, User
    has_many :post_comments_authors, through: [:post, :comments_authors]
  end
end

defmodule Ecto.Integration.PostUser do
  @moduledoc """
  This module is used to test:

    * Many to many associations join_through with schema

  """
  use Ecto.Integration.Schema

  schema Ecto.Integration, "posts_users_pk" do
    belongs_to :user, User
    belongs_to :post, Post
    timestamps()
  end
end

defmodule Ecto.Integration.User do
  @moduledoc """
  This module is used to test:

    * Timestamps
    * Relationships
    * Dependent callbacks

  """
  use Ecto.Integration.Schema

  schema Ecto.Integration, "users" do
    field :name, :string
    has_many :comments, Comment, foreign_key: :author_id, on_delete: :nilify_all, on_replace: :nilify
    has_one :permalink, Permalink, on_replace: :nilify
    has_many :posts, Post, foreign_key: :author_id, on_delete: :nothing, on_replace: :delete
    belongs_to :custom, Custom, references: :bid, type: :binary_id
    many_to_many :schema_posts, Post, join_through: PostUser
    many_to_many :unique_posts, Post, join_through: PostUserCompositePk
    timestamps()
  end
end

defmodule Ecto.Integration.Custom do
  @moduledoc """
  This module is used to test:

    * binary_id primary key
    * Tying another schemas to an existing schema

  Due to the second item, it must be a subset of posts.
  """
  use Ecto.Integration.Schema

  @primary_key {:bid, :binary_id, autogenerate: true}
  schema "customs" do
    field :uuid, Ecto.UUID
  end
end

defmodule Ecto.Integration.Barebone do
  @moduledoc """
  This module is used to test:

    * A schema without primary keys

  """
  use Ecto.Integration.Schema

  @primary_key false
  schema "barebones" do
    field :num, :integer
  end
end

defmodule Ecto.Integration.Tag do
  @moduledoc """
  This module is used to test:

    * The array type
    * Embedding many schemas (uses array)

  """
  use Ecto.Integration.Schema

  schema Ecto.Integration, "tags" do
    field :ints, {:array, :integer}
    field :uuids, {:array, Ecto.UUID}
    embeds_many :items, Item
  end
end

defmodule Ecto.Integration.Item do
  @moduledoc """
  This module is used to test:

    * Embedding

  """
  use Ecto.Schema

  embedded_schema do
    field :price, :integer
    field :valid_at, Ecto.Date
  end
end

defmodule Ecto.Integration.Order do
  @moduledoc """
  This module is used to test:

    * Embedding one schema

  """
  use Ecto.Integration.Schema

  schema Ecto.Integration, "orders" do
    embeds_one :item, Item
  end
end

defmodule Ecto.Integration.CompositePk do
  @moduledoc """
  This module is used to test:

    * Composite primary keys

  """
  use Ecto.Integration.Schema

  @primary_key false
  schema "composite_pk" do
    field :a, :integer, primary_key: true
    field :b, :integer, primary_key: true
    field :name, :string
  end
end

defmodule Ecto.Integration.PostUserCompositePk do
  @moduledoc """
  This module is used to test:

    * Composite primary keys for 2 belongs_to fields

  """
  use Ecto.Integration.Schema

  @primary_key false
  schema Ecto.Integration, "posts_users_composite_pk" do
    belongs_to :user, User, primary_key: true
    belongs_to :post, Post, primary_key: true
    timestamps()
  end
end
