Code.require_file "types.exs", __DIR__

defmodule Ecto.Integration.Post do
  use Ecto.Model

  schema "posts" do
    field :title, :string
    field :counter, :integer, read_after_writes: true
    field :text, :binary
    field :uuid, :uuid
    field :temp, :string, default: "temp", virtual: true
    field :public, :boolean, default: true
    field :cost, :decimal
    field :visits, :integer
    field :intensity, :float
    has_many :comments, Ecto.Integration.Comment
    has_one :permalink, Ecto.Integration.Permalink
    has_many :comments_authors, through: [:comments, :author]
    timestamps
  end
end

defmodule Ecto.Integration.PostUsecTimestamps do
  use Ecto.Model

  schema "posts" do
    field :title, :string
    timestamps usec: true
  end
end

defmodule Ecto.Integration.Comment do
  use Ecto.Model

  schema "comments" do
    field :text, :string
    field :posted, :datetime
    belongs_to :post, Ecto.Integration.Post
    belongs_to :author, Ecto.Integration.User
    has_one :post_permalink, through: [:post, :permalink]
    timestamps
  end
end

defmodule Ecto.Integration.Permalink do
  use Ecto.Model

  @foreign_key_type Custom.Permalink
  schema "permalinks" do
    field :url, :string
    field :lock_version, :integer, default: 1
    belongs_to :post, Ecto.Integration.Post
    has_many :post_comments_authors, through: [:post, :comments_authors]
  end

  optimistic_lock :lock_version
end

defmodule Ecto.Integration.User do
  use Ecto.Model

  schema "users" do
    field :name, :string
    has_many :comments, Ecto.Integration.Comment, foreign_key: :author_id
    belongs_to :custom, Ecto.Integration.Custom, references: :uuid, type: :uuid
  end
end

defmodule Ecto.Integration.Custom do
  use Ecto.Model

  @primary_key {:uuid, :uuid, []}
  schema "customs" do
  end
end

defmodule Ecto.Integration.Barebone do
  use Ecto.Model

  @primary_key false
  schema "barebones" do
    field :num, :integer
  end
end

defmodule Ecto.Integration.Tag do
  use Ecto.Model

  schema "tags" do
    field :ints, {:array, :integer}
    field :uuids, {:array, Ecto.UUID}
  end
end
