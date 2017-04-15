defmodule ApplicationRouter do
  use Dynamo.Router

  prepare do
    conn.fetch([:cookies, :params])
  end

  get "/" do
    conn = conn.assign(:title, "Average Weather by City")
    render conn, "index.html", results: WeatherQueries.all
  end
end
