defmodule Simple.App do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec
    tree = [supervisor(Simple.Repo, [])]
    opts = [name: Simple.Sup, strategy: :one_for_one]
    Supervisor.start_link(tree, opts)
  end
end

defmodule Simple.Repo do
  use Ecto.Repo, otp_app: :simple
end

defmodule Weather do
  use Ecto.Schema
  schema "weather" do
    belongs_to :city, City
    field :wdate, Ecto.Date
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp, :float, default: 0.0
    timestamps
  end
end

defmodule City do
  use Ecto.Schema
  schema "cities" do
    has_many :local_weather, Weather
    belongs_to :country, Country
    field :name, :string
  end
end

defmodule Country do
  use Ecto.Schema
  schema "countries" do
    has_many :cities, City
    # here we associate the `:local_weather` from every City that belongs_to
    # a Country through that Country's `has_many :cities, City` association
    has_many :weather, through: [:cities, :local_weather]
    field :name, :string
  end
end

defmodule Simple do
  import Ecto.Query

  def no_prcp_query do
    query = from w in Weather,
          where: w.prcp <= 0.0 or is_nil(w.prcp),
         select: w
    Simple.Repo.all(query)
  end

  @doc """
  In this function we make a query that returns all Countries
  with their :weather data attached.
  Without `preload: weather` the :weather field for all loaded Countries
  would be an `Ecto.Association.NotLoaded` struct.
  """
  def countries_with_weather_query do
    query = from c in Country,
         preload: :weather
    Simple.Repo.all(query)
  end
end
