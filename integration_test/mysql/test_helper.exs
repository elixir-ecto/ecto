ExUnit.start

alias Ecto.Adapters.Mysql
alias Ecto.Integration.Mysql.TestRepo

defmodule Ecto.Integration.Mysql.CustomAPI do
  use Ecto.Query.Typespec

  deft integer
  defs custom(integer) :: integer
end

defmodule Ecto.Integration.Mysql.TestRepo do
  use Ecto.Repo, adapter: Ecto.Adapters.Mysql

  def url do
    "ecto://root:@localhost:3306/ecto_test"
  end

  def query_apis do
    [Ecto.Integration.Mysql.CustomAPI, Ecto.Query.API]
  end
end

defmodule Ecto.Integration.Mysql.Post do
  use Ecto.Model

  queryable "posts" do
    field :title, :string
    field :text, :string
    field :temp, :virtual, default: "temp"
    field :count, :integer
    has_many :comments, Ecto.Integration.Mysql.Comment
    has_one :permalink, Ecto.Integration.Mysql.Permalink
  end
end

defmodule Ecto.Integration.Mysql.Comment do
  use Ecto.Model

  queryable "comments" do
    field :text, :string
    field :posted, :datetime
    belongs_to :post, Ecto.Integration.Mysql.Post
  end
end

defmodule Ecto.Integration.Mysql.Permalink do
  use Ecto.Model

  queryable "permalinks" do
    field :url, :string
    belongs_to :post, Ecto.Integration.Mysql.Post
  end
end

defmodule Ecto.Integration.Mysql.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__)
      require TestRepo
    end
  end

  setup do
    :ok = Mysql.transaction_begin(TestRepo)
  end

  teardown do
    :ok = Mysql.transaction_rollback(TestRepo)
  end
end

:application.start(:crypto)
:application.start(:emysql)

:emysql.add_pool(:ecto_test_bootstrap, 1, 'root', '', 'localhost', 3306, 'mysql', :utf8)
:emysql.execute(:ecto_test_bootstrap, "DROP DATABASE IF EXISTS ecto_test")
:emysql.execute(:ecto_test_bootstrap, "CREATE DATABASE ecto_test")

:emysql.add_pool(:ecto_test, 1, 'root', '', 'localhost', 3306, 'ecto_test', :utf8)
:emysql.execute(:ecto_test, "CREATE TABLE posts (
                              `id` int(11) AUTO_INCREMENT,
                              `title` varchar(200),
                              `text` varchar(100),
                              `count` int(11),
                              PRIMARY KEY(`id`)
                             ) ENGINE=InnoDB DEFAULT CHARSET=utf8")
:emysql.execute(:ecto_test, "CREATE TABLE comments (
                              `id` int(11) AUTO_INCREMENT,
                              `text` varchar(100),
                              `posted` datetime,
                              `post_id` int(11),
                              PRIMARY KEY(`id`)
                            ) ENGINE=InnoDB DEFAULT CHARSET=utf8")
:emysql.execute(:ecto_test, "CREATE TABLE permalinks (
                              `id` int(11) AUTO_INCREMENT,
                              `url` varchar(100),
                              `post_id` int(11),
                              PRIMARY KEY(`id`)
                            ) ENGINE=InnoDB DEFAULT CHARSET=utf8")

Mysql.start(TestRepo)
