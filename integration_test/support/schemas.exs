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

  schema "posts" do
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
    field :posted, Ecto.Date
    has_many :comments, Ecto.Integration.Comment, on_delete: :delete_all, on_replace: :delete
    has_one :permalink, Ecto.Integration.Permalink, on_delete: :delete_all, on_replace: :delete
    has_many :comments_authors, through: [:comments, :author]
    belongs_to :author, Ecto.Integration.User
    many_to_many :users, Ecto.Integration.User,
      join_through: "posts_users", on_delete: :delete_all, on_replace: :delete
    has_many :users_comments, through: [:users, :comments]
    timestamps
  end

  def changeset(model, params) do
    cast(model, params, [], ~w(counter title text temp public cost visits
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

  schema "comments" do
    field :text, :string
    field :lock_version, :integer, default: 1
    belongs_to :post, Ecto.Integration.Post
    belongs_to :author, Ecto.Integration.User
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

  schema "permalinks" do
    field :url, :string
    belongs_to :post, Ecto.Integration.Post, on_replace: :nilify
    belongs_to :user, Ecto.Integration.User
    has_many :post_comments_authors, through: [:post, :comments_authors]
  end
end

defmodule Ecto.Integration.UserPost do
  @moduledoc """
  This module is used to test:

    * Many to many associations join_through with schema

  """
  use Ecto.Integration.Schema

  schema "users_posts" do
    belongs_to :user, Ecto.Integration.User
    belongs_to :post, Ecto.Integration.Post
    timestamps
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

  schema "users" do
    field :name, :string
    has_many :posts, Ecto.Integration.Post, foreign_key: :author_id, on_delete: :nothing, on_replace: :delete
    has_many :comments, Ecto.Integration.Comment, foreign_key: :author_id, on_delete: :nilify_all, on_replace: :nilify
    has_one :permalink, Ecto.Integration.Permalink, on_replace: :nilify
    belongs_to :custom, Ecto.Integration.Custom, references: :bid, type: :binary_id
    many_to_many :schema_posts, Ecto.Integration.Post, join_through: Ecto.Integration.UserPost
    timestamps
  end
end

defmodule Ecto.Integration.Custom do
  @moduledoc """
  This module is used to test:

    * binary_id primary key
    * Tying another schemas to an existing model

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

    * A model wthout primary keys

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
    * Embedding many models (uses array)

  """
  use Ecto.Integration.Schema

  schema "tags" do
    field :ints, {:array, :integer}
    field :uuids, {:array, Ecto.UUID}
    embeds_many :items, Ecto.Integration.Item
  end
end

defmodule Ecto.Integration.Item do
  @moduledoc """
  This module is used to test:

    * Embedding

  """
  use Ecto.Integration.Schema

  embedded_schema do
    field :price, :integer
    field :valid_at, Ecto.Date
  end
end

defmodule Ecto.Integration.Order do
  @moduledoc """
  This module is used to test:

    * Embedding one model

  """
  use Ecto.Integration.Schema

  schema "orders" do
    embeds_one :item, Ecto.Integration.Item
  end
end
