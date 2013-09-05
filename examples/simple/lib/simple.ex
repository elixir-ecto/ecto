defmodule Simple.App do
  use Application.Behaviour

  def start(_type, _args) do
    Simple.Sup.start_link
  end
end

defmodule Simple.Sup do
  use Supervisor.Behaviour

  def start_link do
    :supervisor.start_link({ :local, __MODULE__ }, __MODULE__, [])
  end

  def init([]) do
    tree = [ worker(Repo, []) ]
    supervise(tree, strategy: :one_for_all)
  end
end

defmodule Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres

  def url do
    "ecto://postgres:postgres@localhost/ecto_simple"
  end
end

defmodule Weather do
  use Ecto.Model

  queryable "weather" do
    field :city, :string
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp, :float, default: 0.0
  end
end

defmodule Simple do
  import Ecto.Query

  def sample_query do
    query = from w in Weather,
          where: w.prcp > 0 or w.prcp == nil,
         select: w
    Repo.all(query)
  end
end
