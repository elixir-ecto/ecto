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
    tree = [ worker(Simple.MyRepo, []) ]
    supervise(tree, strategy: :one_for_all)
  end
end


defmodule Simple.Weather do
  use Ecto.Entity

  dataset :weather, nil do
    field :city, :string
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp, :float
  end
end

defmodule Simple.MyRepo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres

  def url do
    "ecto://postgres:postgres@localhost/postgres"
  end
end

defmodule Simple do
  import Ecto.Query

  def sample_query do
    query = from w in Simple.Weather,
          where: w.prcp > 0 or w.prcp == nil,
         select: w
    Simple.MyRepo.fetch(query)
  end
end
