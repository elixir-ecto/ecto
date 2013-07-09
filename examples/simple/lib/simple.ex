defmodule Simple.App do
  use Application.Behaviour

  def start(_type, _args) do
    Simple.MyRepo.start
  end
end

defmodule Simple.Weather do
  use Ecto.Entity
  table_name :weather

  field :city, :string
  field :temp_lo, :integer
  field :temp_hi, :integer
  field :prcp, :float
end

defmodule Simple.MyRepo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgresql

  def url do
    "ecto://postgres:postgres@localhost/postgres"
  end
end

defmodule Simple do
  import Ecto.Query

  def sample_query do
    query = from(w in Simple.Weather) |> select([w], w)
    Simple.MyRepo.fetch(query)
  end
end
