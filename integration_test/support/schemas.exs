Code.require_file("types.exs", __DIR__)

defmodule Ecto.Integration.Schema do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      type =
        Application.compile_env(:ecto, :primary_key_type) ||
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
    field :blob, :binary
    field :temp, :string, default: "temp", virtual: true
    field :public, :boolean, default: true
    field :cost, :decimal
    field :visits, :integer
    field :wrapped_visits, WrappedInteger
    field :intensity, :float
    field :bid, :binary_id
    field :uuid, Ecto.Integration.TestRepo.uuid(), autogenerate: true
    field :meta, :map
    field :links, {:map, :string}
    field :intensities, {:map, :float}
    field :posted, :date
    has_many :comments, Ecto.Integration.Comment, on_delete: :delete_all, on_replace: :delete
    has_many :force_comments, Ecto.Integration.Comment, on_replace: :delete_if_exists
    has_many :ordered_comments, Ecto.Integration.Comment, preload_order: [:text]
    # The post<->permalink relationship should be marked as uniq
    has_one :permalink, Ecto.Integration.Permalink, on_delete: :delete_all, on_replace: :delete
    has_one :force_permalink, Ecto.Integration.Permalink, on_replace: :delete_if_exists
    has_one :update_permalink, Ecto.Integration.Permalink, foreign_key: :post_id, on_delete: :delete_all, on_replace: :update
    has_many :comments_authors, through: [:comments, :author]
    belongs_to :author, Ecto.Integration.User
    many_to_many :users, Ecto.Integration.User,
      join_through: "posts_users", on_delete: :delete_all, on_replace: :delete
    many_to_many :ordered_users, Ecto.Integration.User, join_through: "posts_users", preload_order: [desc: :name]
    many_to_many :unique_users, Ecto.Integration.User,
      join_through: "posts_users", unique: true
    many_to_many :constraint_users, Ecto.Integration.User,
      join_through: Ecto.Integration.PostUserCompositePk
    has_many :users_comments, through: [:users, :comments]
    has_many :comments_authors_permalinks, through: [:comments_authors, :permalink]
    has_one :post_user_composite_pk, Ecto.Integration.PostUserCompositePk
    timestamps()
  end

  def changeset(schema, params) do
    cast(schema, params, ~w(counter title blob temp public cost visits
                           intensity bid uuid meta posted)a)
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

  def changeset(schema, params) do
    Ecto.Changeset.cast(schema, params, [:text])
  end
end

defmodule Ecto.Integration.Permalink do
  @moduledoc """
  This module is used to test:

    * Field sources
    * Relationships
    * Dependent callbacks

  """
  use Ecto.Integration.Schema

  schema "permalinks" do
    field :url, :string, source: :uniform_resource_locator
    field :title, :string
    field :posted, :date, virtual: true
    belongs_to :post, Ecto.Integration.Post, on_replace: :nilify
    belongs_to :update_post, Ecto.Integration.Post, on_replace: :update, foreign_key: :post_id, define_field: false
    belongs_to :user, Ecto.Integration.User
    has_many :post_comments_authors, through: [:post, :comments_authors]
  end

  def changeset(schema, params) do
    Ecto.Changeset.cast(schema, params, [:url, :title])
  end
end

defmodule Ecto.Integration.PostUser do
  @moduledoc """
  This module is used to test:

    * Many to many associations join_through with schema

  """
  use Ecto.Integration.Schema

  schema "posts_users_pk" do
    belongs_to :user, Ecto.Integration.User
    belongs_to :post, Ecto.Integration.Post
    timestamps()
  end
end

defmodule Ecto.Integration.User do
  @moduledoc """
  This module is used to test:

    * UTC Timestamps
    * Relationships
    * Dependent callbacks

  """
  use Ecto.Integration.Schema

  schema "users" do
    field :name, :string
    has_many :comments, Ecto.Integration.Comment, foreign_key: :author_id, on_delete: :nilify_all, on_replace: :nilify
    has_one :permalink, Ecto.Integration.Permalink, on_replace: :nilify
    has_many :posts, Ecto.Integration.Post, foreign_key: :author_id, on_delete: :nothing, on_replace: :delete
    belongs_to :custom, Ecto.Integration.Custom, references: :bid, type: :binary_id
    many_to_many :schema_posts, Ecto.Integration.Post, join_through: Ecto.Integration.PostUser
    many_to_many :unique_posts, Ecto.Integration.Post, join_through: Ecto.Integration.PostUserCompositePk

    has_many :related_2nd_order_posts, through: [:posts, :users, :posts]
    has_many :users_through_schema_posts, through: [:schema_posts, :users]

    has_many :v2_comments, Ecto.Integration.Comment, foreign_key: :author_id, where: [lock_version: 2]
    has_many :v2_comments_posts, through: [:v2_comments, :post]
    has_many :co_commenters, through: [:comments, :post, :comments_authors]

    timestamps(type: :utc_datetime)
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
    field :uuid, Ecto.Integration.TestRepo.uuid()
    many_to_many :customs, Ecto.Integration.Custom,
      join_through: "customs_customs", join_keys: [custom_id1: :bid, custom_id2: :bid],
      on_delete: :delete_all, on_replace: :delete
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

  schema "tags" do
    field :ints, {:array, :integer}
    field :uuids, {:array, Ecto.Integration.TestRepo.uuid()}
    embeds_many :items, Ecto.Integration.Item
  end
end

defmodule Ecto.Integration.Item do
  @moduledoc """
  This module is used to test:

    * Embedding
    * Preloading associations in embedded schemas

  """
  use Ecto.Schema

  embedded_schema do
    field :reference, PrefixedString
    field :price, :integer
    field :valid_at, :date

    embeds_one :primary_color, Ecto.Integration.ItemColor
    embeds_many :secondary_colors, Ecto.Integration.ItemColor

    belongs_to :user, Ecto.Integration.User
  end
end

defmodule Ecto.Integration.ItemColor do
  @moduledoc """
  This module is used to test:

    * Nested embeds

  """
  use Ecto.Schema

  embedded_schema do
    field :name, :string
  end
end

defmodule Ecto.Integration.Order do
  @moduledoc """
  This module is used to test:

    * Text columns
    * Embedding one schema
    * Preloading items inside embeds_many
    * Preloading items inside embeds_one
    * Field source with json_extract_path

  """
  use Ecto.Integration.Schema

  schema "orders" do
    field :metadata, :map, source: :meta
    embeds_one :item, Ecto.Integration.Item
    embeds_many :items, Ecto.Integration.Item
    belongs_to :permalink, Ecto.Integration.Permalink
  end
end

defmodule Ecto.Integration.CompositePk do
  @moduledoc """
  This module is used to test:

    * Composite primary keys

  """
  use Ecto.Integration.Schema
  import Ecto.Changeset

  @primary_key false
  schema "composite_pk" do
    field :a, :integer, primary_key: true
    field :b, :integer, primary_key: true
    field :name, :string
  end
  def changeset(schema, params) do
    cast(schema, params, ~w(a b name)a)
  end
end

defmodule Ecto.Integration.CorruptedPk do
  @moduledoc """
  This module is used to test:

    * Primary keys that is not unique on a DB side

  """
  use Ecto.Integration.Schema

  @primary_key false
  schema "corrupted_pk" do
    field :a, :string, primary_key: true
  end
end

defmodule Ecto.Integration.PostUserCompositePk do
  @moduledoc """
  This module is used to test:

    * Composite primary keys for 2 belongs_to fields

  """
  use Ecto.Integration.Schema

  @primary_key false
  schema "posts_users_composite_pk" do
    belongs_to :user, Ecto.Integration.User, primary_key: true
    belongs_to :post, Ecto.Integration.Post, primary_key: true
    timestamps()
  end
end

defmodule Ecto.Integration.Usec do
  @moduledoc """
  This module is used to test:

    * usec datetime types

  """
  use Ecto.Integration.Schema

  schema "usecs" do
    field :naive_datetime_usec, :naive_datetime_usec
    field :utc_datetime_usec, :utc_datetime_usec
  end
end

defmodule Ecto.Integration.Logging do
  @moduledoc """
  This module is used to test:

    * Logging the casted version of parameters without array types

  """
  use Ecto.Integration.Schema

  @primary_key {:bid, :binary_id, autogenerate: true}
  schema "loggings" do
    field :int, :integer
    field :uuid, Ecto.Integration.TestRepo.uuid()
    timestamps()
  end
end

defmodule Ecto.Integration.ArrayLogging do
  @moduledoc """
  This module is used to test:

    * Logging the casted version of parameters with array types

  """
  use Ecto.Integration.Schema

  schema "array_loggings" do
    field :uuids, {:array, Ecto.Integration.TestRepo.uuid()}
    timestamps()
  end
end
