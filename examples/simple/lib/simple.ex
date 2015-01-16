defmodule Simple.App do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec
    tree = [worker(Repo, [])]
    opts = [name: Simple.Sup, strategy: :one_for_one]
    Supervisor.start_link(tree, opts)
  end
end

defmodule Repo do
  use Ecto.Repo,
    otp_app: :simple,
    adapter: Ecto.Adapters.Postgres
end

defmodule Weather do
  use Ecto.Model

  schema "weather" do
    field :city, :string
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp, :float, default: 0.0
    timestamps
  end
end

defmodule Simple do
  import Ecto.Query

  def sample_query do
    query = from w in Weather,
          where: w.prcp > 0.0 or is_nil(w.prcp),
         select: w
    Repo.all(query)
  end
end
